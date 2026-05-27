# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

module Async
	module Service
		module Supervisor
			module Envoy
				# Endpoint published to Envoy EDS.
				class Endpoint
					def self.wrap(value)
						case value
						when nil
							nil
						when self
							value
						when Hash
							new(**symbolize_keys(value))
						else
							if value.respond_to?(:address) && value.respond_to?(:port)
								new(
									address: value.address,
									port: value.port,
									hostname: value.respond_to?(:hostname) ? value.hostname : nil
								)
							else
								raise ArgumentError, "Invalid Envoy endpoint: #{value.inspect}"
							end
						end
					end
					
					def self.symbolize_keys(hash)
						hash.each_with_object({}) do |(key, value), result|
							result[key.to_sym] = value
						end
					end
					
					def initialize(address:, port:, hostname: nil, healthy: true)
						@address = address
						@port = port.to_i
						@hostname = hostname
						@healthy = healthy
					end
					
					attr :address
					attr :port
					attr :hostname
					
					def healthy?
						@healthy
					end
					
					def to_h
						{
							address: @address,
							port: @port,
							hostname: @hostname,
							healthy: @healthy
						}.compact
					end
				end
			end
		end
	end
end
