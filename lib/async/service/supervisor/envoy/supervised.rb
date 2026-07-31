# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/service/supervisor/supervised"

module Async
	module Service
		module Supervisor
			module Envoy
				# Registers bound Falcon listeners with the supervisor.
				module Supervised
					include Async::Service::Supervisor::Supervised
					
					# Prepare and register a worker after its listener has been bound.
					# @parameter instance [Async::Container::Instance] The container instance.
					# @parameter listener [Object] The bound listener descriptor.
					def prepare_worker!(instance, listener:)
						prepare!(instance, state: {endpoint: envoy_endpoint(listener)})
					end
					
					# Convert a bound listener into serialized Envoy endpoint state.
					# @parameter listener [Object] The bound listener descriptor.
					# @returns [Hash] The serialized endpoint.
					def envoy_endpoint(listener)
						{
							name: listener.name,
							scheme: listener.scheme,
							protocols: listener.protocols,
							addresses: listener.addresses.map{|address| envoy_address(address)},
						}
					end
					
					# Convert a concrete bound address to serializable supervisor state.
					# @parameter address [Addrinfo] The bound address.
					# @returns [Hash] The serialized address.
					# @raises [ArgumentError] If the address family is unsupported.
					def envoy_address(address)
						if address.ip?
							{address: address.ip_address, port: address.ip_port}
						elsif address.unix?
							{path: address.unix_path}
						else
							raise ArgumentError, "Unsupported listener address: #{address.inspect}"
						end
					end
				end
			end
		end
	end
end
