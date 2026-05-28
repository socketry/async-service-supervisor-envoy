# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

# @namespace
module Async
	# @namespace
	module Service
		# @namespace
		module Supervisor
			# Provides Envoy integration for supervisor-managed services.
			module Envoy
				# Represents an endpoint published to Envoy EDS.
				class Endpoint
					# Wrap an endpoint-like value.
					# @parameter value [Endpoint | Hash | Object | Nil] The endpoint value to wrap.
					# @returns [Endpoint | Nil] The wrapped endpoint, or `nil` if no endpoint was supplied.
					# @raises [ArgumentError] If the value cannot be converted to an endpoint.
					def self.wrap(value)
						case value
						when nil
							nil
						when self
							value
						when Hash
							new(**symbolize_keys(value))
						else
							raise ArgumentError, "Invalid Envoy endpoint: #{value.inspect}"
						end
					end
					
					# Convert hash keys to symbols.
					# @parameter hash [Hash] The hash to convert.
					# @returns [Hash] A copy of the hash with symbol keys.
					def self.symbolize_keys(hash)
						hash.each_with_object({}) do |(key, value), result|
							result[key.to_sym] = value
						end
					end
					
					private_class_method :symbolize_keys
					
					# Initialize the endpoint.
					# @parameter name [String | Nil] The optional endpoint name.
					# @parameter address [String] The endpoint IP address or hostname.
					# @parameter port [Integer] The endpoint port.
					# @parameter hostname [String | Nil] The optional endpoint hostname.
					# @parameter protocol [String | Symbol | Nil] The optional endpoint protocol.
					# @parameter healthy [Boolean] Whether the endpoint should be published as healthy.
					def initialize(address:, port:, name: nil, hostname: nil, protocol: nil, healthy: true)
						@name = name
						@address = address
						@port = port.to_i
						@hostname = hostname
						@protocol = protocol
						@healthy = healthy
					end
					
					# @attribute [String | Nil] The optional endpoint name.
					attr :name
					
					# @attribute [String] The endpoint IP address or hostname.
					attr :address
					
					# @attribute [Integer] The endpoint port.
					attr :port
					
					# @attribute [String | Nil] The optional endpoint hostname.
					attr :hostname
					
					# @attribute [String | Symbol | Nil] The optional endpoint protocol.
					attr :protocol
					
					# Whether the endpoint is healthy.
					# @returns [Boolean] Returns `true` when the endpoint should be published as healthy.
					def healthy?
						@healthy
					end
					
					# Convert the endpoint to a hash suitable for the xDS control plane.
					# @returns [Hash] The endpoint attributes.
					def to_h
						{
							name: @name,
							address: @address,
							port: @port,
							hostname: @hostname,
							protocol: @protocol,
							healthy: @healthy
						}.compact
					end
				end
			end
		end
	end
end
