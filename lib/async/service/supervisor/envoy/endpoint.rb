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
							new(**value)
						else
							raise ArgumentError, "Invalid Envoy endpoint: #{value.inspect}"
						end
					end
					
					# Normalize a concrete endpoint address.
					# @parameter value [Hash] The address value.
					# @returns [Hash] A normalized IP or Unix address.
					def self.normalize_address(value)
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
					# @parameter protocols [Array(String)] The supported upstream HTTP protocol names.
					# @parameter addresses [Array(Hash)] The grouped concrete addresses.
					def initialize(name:, scheme:, protocols:, addresses:)
						@name = name.to_s
						@scheme = scheme.to_sym
						@protocols = protocols.map(&:to_s).uniq.freeze
						raise ArgumentError, "An endpoint requires at least one protocol!" if @protocols.empty?
						@addresses = addresses.map{|value| self.class.normalize_address(value)}.freeze
						raise ArgumentError, "An endpoint requires at least one address!" if @addresses.empty?
					end
					
					# @attribute [String] The upstream cluster name.
					attr :name
					
					# @attribute [Symbol] The upstream application scheme.
					attr :scheme
					
					# @attribute [Array(String)] The supported upstream HTTP protocol names.
					attr :protocols
					
					# @attribute [Array(Hash)] The grouped concrete addresses.
					attr :addresses
					
				end
			end
		end
	end
end
