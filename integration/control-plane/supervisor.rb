# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async"
require "async/service/supervisor/server"
require "async/service/supervisor/utilization_monitor"
require "async/service/supervisor/envoy"
require "io/endpoint/generic"
require "io/endpoint/host_endpoint"

def endpoint(value)
	IO::Endpoint::Generic.parse(value)
end

Sync do
	supervisor_endpoint = endpoint(ENV.fetch("SUPERVISOR_ENDPOINT"))
	orca = ENV.fetch("ORCA", "false") == "true"
	
	utilization_monitor = if orca
		Async::Service::Supervisor::UtilizationMonitor.new(
			path: ENV.fetch("UTILIZATION_PATH", "utilization.shm"),
			interval: 1
		)
	end
	
	monitor = Async::Service::Supervisor::Envoy::Monitor.new(
		bind: ENV.fetch("XDS_BIND"),
		publish_clusters: ENV.fetch("PUBLISH_CLUSTERS", "true") == "true",
		orca: orca,
		utilization_monitor: utilization_monitor
	)
	
	server = Async::Service::Supervisor::Server.new(
		endpoint: supervisor_endpoint,
		monitors: [utilization_monitor, monitor].compact
	)
	
	server.run
end
