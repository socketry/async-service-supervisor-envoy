# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require_relative "endpoint"

module Async
	module Service
		module Supervisor
			module Envoy
				# Maps supervisor state into Envoy upstream endpoints.
				class Delegate
					# Extract serialized endpoints from a supervisor controller.
					# @parameter supervisor_controller [Object] The supervisor controller describing the worker.
					# @returns [Hash | Array(Hash) | Nil] The serialized endpoint state.
					def endpoints(supervisor_controller)
						state = supervisor_controller.state
						
						state[:endpoints] || state["endpoints"] || state[:endpoint] || state["endpoint"]
					end
					
					# Convert serialized state into Envoy endpoint values.
					# @parameter supervisor_controller [Object] The supervisor controller describing the worker.
					# @returns [Array(Endpoint)] The upstream endpoints to publish.
					def endpoint_list(supervisor_controller)
						case endpoints = self.endpoints(supervisor_controller)
						when nil
							[]
						when Array
							endpoints.map{|endpoint| Endpoint.wrap(endpoint)}
						else
							[Endpoint.wrap(endpoints)]
						end
					end
					
					# Select the Envoy cluster name for an endpoint.
					# @parameter supervisor_controller [Object] The supervisor controller describing the worker.
					# @parameter endpoint [Endpoint] The endpoint being published.
					# @returns [String | Nil] The cluster name, or nil to skip the endpoint.
					def cluster(supervisor_controller, endpoint)
						endpoint.name
					end
					
					# Determine whether an endpoint should be published as healthy.
					# @parameter supervisor_controller [Object] The supervisor controller describing the worker.
					# @parameter endpoint [Endpoint] The endpoint being published.
					# @returns [Boolean] Whether the endpoint is healthy.
					def healthy?(supervisor_controller, endpoint)
						true
					end
				end
			end
		end
	end
end
