# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/http/endpoint"
require "async/service/supervisor/monitor"
require "async/grpc/xds/control_plane"
require "async/grpc/xds/server"
require "set"

require_relative "endpoint"

# @namespace
module Async
	# @namespace
	module Service
		# @namespace
		module Supervisor
			# Provides Envoy integration for supervisor-managed services.
			module Envoy
				# Represents a supervisor monitor that publishes worker endpoints to Envoy using xDS.
				class Monitor < Async::Service::Supervisor::Monitor
					# Initialize the monitor.
					# @parameter bind [String | Nil] The optional address for the xDS control plane server.
					# @parameter cluster [Proc | String | Symbol] The cluster name or callable used to derive it from a supervisor controller.
					# @parameter include [Proc | Object] The endpoint value or callable used to select workers for publication.
					# @parameter health [Proc | Boolean] The health value or callable used to derive endpoint health.
					# @parameter control_plane [Async::GRPC::XDS::ControlPlane] The xDS control plane to update.
					def initialize(
						bind: nil,
						cluster: -> controller{controller.state[:name]},
						include: -> controller{controller.state[:endpoint]},
						health: -> controller{true},
						control_plane: Async::GRPC::XDS::ControlPlane.new,
						**options
					)
						super(**options)
						
						@bind = bind
						@cluster = cluster
						@include = binding.local_variable_get(:include)
						@health = health
						@control_plane = control_plane
						@workers = {}
						@clusters = Set.new
						@server_task = nil
						@mutex = Mutex.new
					end
					
					# @attribute [Async::GRPC::XDS::ControlPlane] The xDS control plane receiving cluster and endpoint updates.
					attr :control_plane
					
					# Register a supervisor worker with Envoy.
					# @parameter supervisor_controller [Object] The supervisor controller describing the worker.
					# @returns [void]
					def register(supervisor_controller)
						@mutex.synchronize do
							if record = build_record(supervisor_controller)
								@workers[supervisor_controller.id] = record
								@clusters.add(record[:cluster])
								publish_cluster(record[:cluster])
							end
							
							publish_endpoints
						end
					end
					
					# Remove a supervisor worker from Envoy.
					# @parameter supervisor_controller [Object] The supervisor controller describing the worker.
					# @returns [void]
					def remove(supervisor_controller)
						@mutex.synchronize do
							@workers.delete(supervisor_controller.id)
							publish_endpoints
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
								clusters: clusters.transform_values do |records|
									records.map{|record| record[:endpoint].to_h}
								end
							}
						end
					end
					
					# Refresh endpoint health and publish updated EDS state.
					# @returns [void]
					def run_once
						@mutex.synchronize do
							@workers.each_value do |record|
								record[:endpoint] = record[:endpoint].class.new(
									address: record[:endpoint].address,
									port: record[:endpoint].port,
									hostname: record[:endpoint].hostname,
									healthy: healthy?(record[:controller])
								)
							end
							
							publish_endpoints
						end
					end
					
					private
					
					def build_record(supervisor_controller)
						cluster = call(@cluster, supervisor_controller)
						endpoint = Endpoint.wrap(call(@include, supervisor_controller))
						return unless cluster && endpoint
						
						{
							controller: supervisor_controller,
							cluster: cluster.to_s,
							endpoint: Endpoint.new(
								address: endpoint.address,
								port: endpoint.port,
								hostname: endpoint.hostname,
								healthy: healthy?(supervisor_controller)
							)
						}
					end
					
					def healthy?(supervisor_controller)
						!!call(@health, supervisor_controller)
					end
					
					def call(callable, supervisor_controller)
						if callable.respond_to?(:call)
							callable.call(supervisor_controller)
						else
							callable
						end
					end
					
					def publish_cluster(cluster)
						@control_plane.update_cluster(cluster)
					end
					
					def publish_endpoints
						grouped = clusters
						
						@clusters.each do |cluster|
							@control_plane.update_endpoints(
								cluster,
								grouped.fetch(cluster, []).map{|record| record[:endpoint].to_h}
							)
						end
					end
					
					def clusters
						@workers.each_value.group_by{|record| record[:cluster]}
					end
				end
			end
		end
	end
end
