# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require_relative "endpoint"

# @namespace
module Async
	# @namespace
	module Service
		# @namespace
		module Supervisor
			# Provides Envoy integration for supervisor-managed services.
			module Envoy
				# Maps supervisor controller state into Envoy endpoint records.
				class Delegate
					# Extract endpoint state from the supervisor controller.
					# @parameter supervisor_controller [Object] The supervisor controller describing the worker.
					# @returns [Endpoint | Array(Endpoint) | Hash | Array(Hash) | Nil] The endpoint state to publish.
					def endpoints(supervisor_controller)
						state = supervisor_controller.state
						
						state[:endpoints] || state["endpoints"] || state[:endpoint] || state["endpoint"]
					end
					
					# Convert endpoint state into endpoint values.
					# @parameter supervisor_controller [Object] The supervisor controller describing the worker.
					# @returns [Array(Endpoint)] The endpoints to publish.
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
						state = supervisor_controller.state
						
						endpoint.name || state[:name] || state["name"]
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
