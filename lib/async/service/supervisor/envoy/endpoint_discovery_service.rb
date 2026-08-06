# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/grpc/service"
require "async/grpc/xds/control_plane"
require "async/grpc/xds/service"
require "envoy/service/discovery/v3/discovery_pb"
require "protocol/grpc/interface"

module Async
	module Service
		module Supervisor
			module Envoy
				# Serves Envoy Endpoint Discovery Service requests from a control plane.
				#
				# The supervisor only ever publishes endpoint assignments, so it serves EDS
				# directly rather than aggregating resource types. This leaves the ADS
				# transport unclaimed for cluster, listener and route configuration.
				class EndpointDiscoveryService < Async::GRPC::Service
					SERVICE_NAME = "envoy.service.endpoint.v3.EndpointDiscoveryService"
					
					# The only resource type this service serves.
					RESOURCE_TYPE = Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE
					
					# Interface definition for the Endpoint Discovery Service.
					class Interface < Protocol::GRPC::Interface
						rpc :StreamEndpoints,
							request_class: ::Envoy::Service::Discovery::V3::DiscoveryRequest,
							response_class: ::Envoy::Service::Discovery::V3::DiscoveryResponse,
							streaming: :bidirectional
					end
					
					# Initialize an Endpoint Discovery Service.
					# @parameter control_plane [Async::GRPC::XDS::ControlPlane] The control plane that provides endpoint assignments.
					def initialize(control_plane)
						super(Interface, SERVICE_NAME)
						
						@control_plane = control_plane
					end
					
					# Serve a state-of-the-world Endpoint Discovery Service stream.
					# @parameter input [Enumerable] The stream of discovery requests.
					# @parameter output [Interface(:write)] The discovery response stream.
					# @parameter call [Protocol::GRPC::Call] The gRPC call context.
					# @asynchronous
					def stream_endpoints(input, output, call)
						stream = Async::GRPC::XDS::Service::Stream.new(@control_plane, output)
						@control_plane.register_stream(stream)
						
						reader = Async do
							input.each do |request|
								stream.request(normalize(request))
							end
						end
						
						writer = Async do
							stream.run
						end
						
						reader.wait
					ensure
						stream&.close
						reader&.stop
						writer&.stop
						@control_plane.remove_stream(stream) if stream
					end
					
					private
					
					# Pin a request to this service's resource type. A dedicated discovery
					# service implies its own type, so clients may omit it, and a client
					# cannot use this stream to subscribe to anything else.
					def normalize(request)
						return request if request.type_url == RESOURCE_TYPE
						
						request = request.dup
						request.type_url = RESOURCE_TYPE
						request
					end
				end
			end
		end
	end
end
