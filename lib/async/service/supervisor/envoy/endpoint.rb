# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

module Async
	module Service
		module Supervisor
			module Envoy
				# Represents one upstream endpoint published to Envoy EDS.
				class Endpoint
					# Wrap serialized endpoint state.
					# @parameter value [Endpoint | Hash] The value to wrap.
					# @returns [Endpoint] The endpoint value.
					def self.wrap(value)
						case value
						when self
							value
						when Hash
							attributes = value.each_with_object({}) do |(key, item), result|
								result[key.to_sym] = item
							end
							
							new(**attributes)
						else
							raise ArgumentError, "Invalid Envoy endpoint: #{value.inspect}"
						end
					end
					
					# Normalize a concrete endpoint address.
					# @parameter value [Hash] The address value.
					# @returns [Hash] A normalized IP or Unix address.
					def self.normalize_address(value)
						value = value.each_with_object({}) do |(key, item), result|
							result[key.to_sym] = item
						end
						
						if path = value[:path]
							raise ArgumentError, "A Unix endpoint cannot specify an IP address or port!" if value[:address] || value[:port]
							
							{path: path.to_s}.freeze
						elsif value[:address] && value[:port]
							{address: value[:address].to_s, port: Integer(value[:port])}.freeze
						else
							raise ArgumentError, "An endpoint address requires either path, or address and port: #{value.inspect}"
						end
					end
					
					# Initialize an endpoint.
					# @parameter name [String] The upstream cluster name.
					# @parameter scheme [String | Symbol] The upstream application scheme.
					# @parameter protocol [String | Symbol] The upstream HTTP protocol.
					# @parameter addresses [Array(Hash)] The grouped concrete addresses.
					# @parameter healthy [Boolean] Whether the endpoint is healthy.
					def initialize(name:, scheme:, protocol:, addresses:, healthy: true)
						@name = name.to_s
						@scheme = scheme.to_sym
						@protocol = protocol.to_sym
						@addresses = addresses.map{|value| self.class.normalize_address(value)}.freeze
						raise ArgumentError, "An endpoint requires at least one address!" if @addresses.empty?
						
						@healthy = healthy
					end
					
					# @attribute [String] The upstream cluster name.
					attr :name
					
					# @attribute [Symbol] The upstream application scheme.
					attr :scheme
					
					# @attribute [Symbol] The upstream HTTP protocol.
					attr :protocol
					
					# @attribute [Array(Hash)] The grouped concrete addresses.
					attr :addresses
					
					# Whether the endpoint is healthy.
					# @returns [Boolean] Whether the endpoint is healthy.
					def healthy?
						@healthy
					end
					
					# Convert the endpoint to an xDS control-plane hash.
					# @returns [Hash] The endpoint attributes.
					def to_h
						{addresses: @addresses, healthy: @healthy}
					end
				end
			end
		end
	end
end
