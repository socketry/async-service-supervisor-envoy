# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

module Async
	module Service
		module Supervisor
			module Envoy
				# Represents an upstream endpoint published to Envoy EDS.
				class Endpoint
					# Build an immutable endpoint.
					# @parameter name [String] The upstream cluster name.
					# @parameter scheme [String | Symbol] The upstream application scheme.
					# @parameter protocols [Array(String)] The supported upstream HTTP protocol names.
					# @parameter addresses [Array(Hash)] The grouped concrete addresses.
					# @returns [Endpoint] The immutable endpoint.
					def self.build(name:, scheme:, protocols:, addresses:)
						new(
							name.to_s,
							scheme.to_sym,
							protocols.map(&:to_s).uniq,
							addresses,
						).tap(&:freeze)
					end
					
					# Wrap serialized endpoint state.
					# @parameter value [Endpoint | Hash] The value to wrap.
					# @returns [Endpoint] The endpoint value.
					def self.wrap(value)
						case value
						when self
							value
						when Hash
							build(**value)
						else
							raise ArgumentError, "Invalid Envoy endpoint: #{value.inspect}"
						end
					end
					
					# Initialize an endpoint.
					# @parameter name [String] The upstream cluster name.
					# @parameter scheme [Symbol] The upstream application scheme.
					# @parameter protocols [Array(String)] The supported upstream HTTP protocol names.
					# @parameter addresses [Array(Hash)] The grouped concrete addresses.
					def initialize(name, scheme, protocols, addresses)
						@name = name
						@scheme = scheme
						@protocols = protocols
						raise ArgumentError, "An endpoint requires at least one protocol!" if @protocols.empty?
						@addresses = addresses
						raise ArgumentError, "An endpoint requires at least one address!" if @addresses.empty?
						
						@hash = nil
					end
					
					# @attribute [String] The upstream cluster name.
					attr :name
					
					# @attribute [Symbol] The upstream application scheme.
					attr :scheme
					
					# @attribute [Array(String)] The supported upstream HTTP protocol names.
					attr :protocols
					
					# @attribute [Array(Hash)] The grouped concrete addresses.
					attr :addresses
					
					# Freeze this endpoint and cache its value hash.
					def freeze
						return self if frozen?
						
						@name.freeze
						@protocols.each(&:freeze).freeze
						@addresses.each do |address|
							address.each_value(&:freeze)
							address.freeze
						end.freeze
						@hash = self.hash
						
						super
					end
					
					# Compare this endpoint with another endpoint by value.
					# @parameter other [Object] The object to compare.
					# @returns [Boolean] Whether both endpoints have identical values.
					def eql?(other)
						other.instance_of?(self.class) &&
							@name == other.name &&
							@scheme == other.scheme &&
							@protocols == other.protocols &&
							@addresses == other.addresses
					end
					
					alias == eql?
					
					# Compute the value hash used when grouping endpoints.
					# @returns [Integer] The endpoint value hash.
					def hash
						@hash || [self.class, @name, @scheme, @protocols, @addresses].hash
					end
				end
			end
		end
	end
end
