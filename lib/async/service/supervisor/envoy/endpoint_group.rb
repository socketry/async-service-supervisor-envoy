# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

module Async
	module Service
		module Supervisor
			module Envoy
				# Groups the workers reporting a single upstream endpoint.
				class EndpointGroup
					# Initialize an endpoint group.
					# @parameter endpoint [Endpoint] The endpoint shared by the workers.
					def initialize(endpoint)
						@endpoint = endpoint
						@workers = {}
					end
					
					# @attribute [Endpoint] The endpoint shared by the workers.
					attr :endpoint
					
					# Add or update a worker report.
					# @parameter worker [SupervisorController] The worker reporting the endpoint.
					# @parameter healthy [Boolean] Whether the worker considers the endpoint healthy.
					def add(worker, healthy:)
						@workers[worker.id] = healthy
					end
					
					# Remove a worker report.
					# @parameter worker [SupervisorController] The worker to remove.
					# @returns [Boolean | Nil] The removed health value, if present.
					def remove(worker)
						@workers.delete(worker.id)
					end
					
					# Count the workers reporting this endpoint.
					# @returns [Integer] The number of reporting workers.
					def size
						@workers.size
					end
					
					# Determine whether any workers report this endpoint.
					# @returns [Boolean] Whether the group has no workers.
					def empty?
						@workers.empty?
					end
					
					# Determine the aggregate endpoint health.
					# @returns [Boolean] Whether any reporting worker is healthy.
					def healthy?
						@workers.each_value.any?
					end
					
					# Convert the group to an xDS endpoint description.
					# @returns [Hash] The endpoint addresses and aggregate health.
					def as_json
						{addresses: @endpoint.addresses, healthy: healthy?}
					end
				end
			end
		end
	end
end
