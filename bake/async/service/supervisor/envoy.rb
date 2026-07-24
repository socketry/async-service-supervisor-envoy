# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

# Get the running Envoy monitor status from the supervisor.
def status
	envoy_status
end

# Get the clusters currently published by the running Envoy monitor.
def clusters
	fetch_clusters
end

# Get a compact endpoint list from the running Envoy monitor.
def endpoints
	fetch_clusters.flat_map do |cluster, entries|
		entries.map do |entry|
			entry.merge(cluster: cluster)
		end
	end
end

private

def supervisor_status
	context["async:service:supervisor:status"].call
end

def envoy_status
	status = supervisor_status
	monitor = status.find do |entry|
		entry[:type] == "Async::Service::Supervisor::Envoy::Monitor"
	end
	
	unless monitor
		raise "No Async::Service::Supervisor::Envoy::Monitor status found."
	end
	
	monitor
end

def fetch_clusters
	status = envoy_status
	status.fetch(:data).fetch(:clusters)
end
