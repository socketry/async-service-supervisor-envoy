# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/http/endpoint"
require "async/service/supervisor/monitor"
require "async/grpc/xds/control_plane"
require "async/grpc/xds/server"

require_relative "delegate"
require_relative "endpoint"

module Async
	module Service
		module Supervisor
			# Provides Envoy integration for supervisor-managed services.
			module Envoy
				# Represents a supervisor monitor that publishes worker endpoints to Envoy using xDS.
				class Monitor < Async::Service::Supervisor::Monitor
					# Initialize the monitor.
					# @parameter bind [String | Nil] The optional address for the xDS control plane server.
					# @parameter delegate [Delegate] The delegate used to map supervisor state into Envoy endpoints.
					# @parameter control_plane [Async::GRPC::XDS::ControlPlane] The xDS control plane to update.
					def initialize(
						bind: nil,
						delegate: Delegate.new,
						control_plane: Async::GRPC::XDS::ControlPlane.new,
						**options
					)
						super(**options)
						
						@bind = bind
						@delegate = delegate
						@control_plane = control_plane
						@controllers = {}
						@published_clusters = {}
						@server_task = nil
						@mutex = Mutex.new
					end
					
					# @attribute [Async::GRPC::XDS::ControlPlane] The xDS control plane receiving cluster and endpoint updates.
					attr :control_plane
					
					# @attribute [Delegate] The delegate used to map supervisor state into Envoy endpoints.
					attr :delegate
					
					# Register a supervisor worker with Envoy.
					# @parameter supervisor_controller [Object] The supervisor controller describing the worker.
					# @returns [void]
					def register(supervisor_controller)
						@mutex.synchronize do
							@controllers[supervisor_controller.id] = supervisor_controller
							reconcile
						end
					end
					
					# Remove a supervisor worker from Envoy.
					# @parameter supervisor_controller [Object] The supervisor controller describing the worker.
					# @returns [void]
					def remove(supervisor_controller)
						@mutex.synchronize do
							@controllers.delete(supervisor_controller.id)
							reconcile
						end
					end
					
					# Run the monitor and optional xDS server task.
					# @parameter parent [Async::Task] The parent task used for the xDS server.
					# @returns [Async::Task] The monitor task.
					def run(parent: Async::Task.current)
						task = super(parent: parent)
						
						if @bind
							@server_task = parent.async do
								endpoint = Async::HTTP::Endpoint.parse(@bind, protocol: Async::HTTP::Protocol::HTTP2)
								Async::GRPC::XDS::Server.new(@control_plane).run(endpoint)
							end
						end
						
						task
					end
					
					# Convert the currently published endpoints to JSON-compatible data.
					# @returns [Hash] The clusters and endpoint hashes.
					def as_json
						@mutex.synchronize do
							{
								clusters: build_clusters
							}
						end
					end
					
					# Refresh endpoint health and publish updated EDS state.
					# @returns [void]
					def run_once
						@mutex.synchronize do
							reconcile
						end
					end
					
					private
					
					def build_record(supervisor_controller, endpoint)
						cluster = @delegate.cluster(supervisor_controller, endpoint)
						return unless cluster
						
						{
							cluster: cluster.to_s,
							endpoint: endpoint,
							healthy: @delegate.healthy?(supervisor_controller, endpoint),
						}
					end
					
					def build_records(supervisor_controller)
						@delegate.endpoint_list(supervisor_controller).filter_map do |endpoint|
							build_record(supervisor_controller, endpoint)
						end
					end
					
					def reconcile
						records_by_cluster = build_records_by_cluster
						clusters = build_clusters(records_by_cluster)
						
						records_by_cluster.each do |cluster, records|
							configuration = cluster_configuration(records)
							
							unless @published_clusters[cluster] == configuration
								@control_plane.update_cluster(cluster, **configuration)
								@published_clusters[cluster] = configuration
							end
						end
						
						(@published_clusters.keys | clusters.keys).each do |cluster|
							@control_plane.update_endpoints(cluster, clusters.fetch(cluster, []))
						end
					end
					
					def build_records_by_cluster
						@controllers.each_value.flat_map do |controller|
							build_records(controller)
						end.group_by do |record|
							record[:cluster]
						end
					end
					
					def build_clusters(records_by_cluster = build_records_by_cluster)
						records_by_cluster.transform_values do |records|
							records.group_by{|record| record[:endpoint].addresses}.map do |addresses, records|
								{addresses: addresses, healthy: records.any?{|record| record[:healthy]}}
							end
						end
					end
					
					def cluster_configuration(records)
						schemes = records.map{|record| record[:endpoint].scheme}.uniq
						protocols = records.map{|record| record[:endpoint].protocols}
						common_protocols = protocols.reduce{|common, names| common & names}
						
						raise ArgumentError, "Envoy cluster contains incompatible schemes: #{schemes.inspect}" if schemes.size > 1
						raise ArgumentError, "Envoy cluster contains no common protocols: #{protocols.inspect}" if common_protocols.empty?
						raise ArgumentError, "HTTPS upstream endpoints are not yet supported!" if schemes.first == :https
						
						{protocol: envoy_protocol(common_protocols)}
					end
					
					def envoy_protocol(protocols)
						protocols.each do |protocol|
							case protocol
							when "h2"
								return :http2
							when "http/1.1", "http/1.0"
								return :http1
							end
						end
						
						raise ArgumentError, "Envoy cluster contains no supported protocols: #{protocols.inspect}"
					end
				end
			end
		end
	end
end
