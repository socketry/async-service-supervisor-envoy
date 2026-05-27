# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/http/endpoint"
require "async/service/supervisor/monitor"
require "async/grpc/xds/control_plane"
require "async/grpc/xds/server"
require "set"

require_relative "endpoint"

module Async
	module Service
		module Supervisor
			module Envoy
				# Publishes supervisor workers to Envoy using xDS CDS/EDS.
				class Monitor < Async::Service::Supervisor::Monitor
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
					
					attr :control_plane
					
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
					
					def remove(supervisor_controller)
						@mutex.synchronize do
							@workers.delete(supervisor_controller.id)
							publish_endpoints
						end
					end
					
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
					
					def as_json
						@mutex.synchronize do
							{
								clusters: clusters.transform_values do |records|
									records.map{|record| record[:endpoint].to_h}
								end
							}
						end
					end
					
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
