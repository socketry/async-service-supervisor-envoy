# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/http/protocol/http2"
require "async/service/supervisor/supervised"

module Async
	module Service
		module Supervisor
			module Envoy
				# Registers post-bind cluster listeners with the supervisor.
				module Supervised
					include Async::Service::Supervisor::Supervised
					
					# Prepare and register a worker after its listener has been bound.
					# @parameter instance [Async::Container::Instance] The container instance.
					# @parameter listener [Object] The bound listener descriptor.
					def prepare_worker!(instance, listener:)
						state = supervisor_worker_state.merge(endpoint: envoy_endpoint(listener))
						prepare!(instance, state: state)
					end
					
					# Convert a bound listener into serialized Envoy endpoint state.
					# @parameter listener [Object] The bound listener descriptor.
					# @returns [Hash] The serialized endpoint.
					def envoy_endpoint(listener)
						{
							name: listener.name,
							scheme: listener.scheme,
							protocol: envoy_protocol(listener.protocol),
							addresses: listener.addresses.filter_map{|address| envoy_address(address)},
						}
					end
					
					# Convert an application protocol implementation to an Envoy upstream protocol.
					# @parameter protocol [Object] The application protocol implementation.
					# @returns [Symbol] The Envoy upstream protocol.
					def envoy_protocol(protocol)
						if protocol.equal?(Async::HTTP::Protocol::HTTP2)
							:http2
						else
							:http1
						end
					end
					
					# Convert a concrete bound address to serializable supervisor state.
					# @parameter address [Addrinfo] The bound address.
					# @returns [Hash | Nil] The serialized address, or nil if unsupported.
					def envoy_address(address)
						if address.ip?
							{address: address.ip_address, port: address.ip_port}
						elsif address.unix?
							{path: address.unix_path}
						end
					end
				end
			end
		end
	end
end
