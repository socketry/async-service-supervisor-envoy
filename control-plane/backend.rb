# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async"
require "async/http/protocol/http1"
require "async/service/supervisor/worker"
require "falcon/server"
require "io/endpoint/generic"
require "io/endpoint/host_endpoint"
require "socket"

backend_id = ENV.fetch("BACKEND_ID")
backend_port = Integer(ENV.fetch("BACKEND_PORT"))
service_name = ENV.fetch("SERVICE_NAME")
backend_address = IPSocket.getaddress(Socket.gethostname)

rack_application = proc do |env|
	body = "Hello from #{backend_id}\n"
	
	[
		200,
		{
			"content-type" => "text/plain",
			"x-backend-id" => backend_id,
			"content-length" => body.bytesize.to_s
		},
		[body]
	]
end

Sync do |task|
	supervisor_endpoint = IO::Endpoint::Generic.parse(ENV.fetch("SUPERVISOR_ENDPOINT"))
	http_endpoint = IO::Endpoint.tcp("0.0.0.0", backend_port)
	
	middleware = Falcon::Server.middleware(rack_application, cache: false)
	server = Falcon::Server.new(
		middleware,
		http_endpoint,
		protocol: Async::HTTP::Protocol::HTTP1,
		scheme: "http"
	)
	
	worker = Async::Service::Supervisor::Worker.new(
		endpoint: supervisor_endpoint,
		state: {
			name: service_name,
			endpoint: {
				address: backend_address,
				port: backend_port
			}
		}
	)
		
	worker.run
	server.run
end
	