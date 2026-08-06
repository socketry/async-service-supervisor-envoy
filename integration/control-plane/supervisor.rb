# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async"
require "async/service/supervisor/server"
require "async/service/supervisor/envoy"
require "io/endpoint/generic"
require "io/endpoint/host_endpoint"

def endpoint(value)
	IO::Endpoint::Generic.parse(value)
end

Sync do
	supervisor_endpoint = endpoint(ENV.fetch("SUPERVISOR_ENDPOINT"))
	monitor = Async::Service::Supervisor::Envoy::Monitor.new(
		bind: ENV.fetch("XDS_BIND")
	)
	
	server = Async::Service::Supervisor::Server.new(
		endpoint: supervisor_endpoint,
		monitors: [monitor]
	)
	
	server.run
end
