#!/usr/bin/env async-service
# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/service/supervisor"
require "async/service/supervisor/envoy"
require "falcon/environment/cluster"
require "fileutils"
require "io/endpoint/unix_endpoint"

service_name = ENV.fetch("SERVICE_NAME", "hello-world")
xds_bind = ENV.fetch("XDS_BIND", "http://127.0.0.1:18000")
socket_directory = File.expand_path(ENV.fetch("SOCKET_DIRECTORY", "sockets"), __dir__)
FileUtils.mkdir_p(socket_directory)

service service_name do
	include Falcon::Environment::Cluster
	include Async::Service::Supervisor::Envoy::Supervised
	
	count 2
	
	endpoint do
		worker_id = "#{Process.pid}-#{Thread.current.object_id}"
		transport = IO::Endpoint.unix(File.join(socket_directory, "#{worker_id}.ipc"))
		
		Async::HTTP::Endpoint.parse(
			"http://localhost",
			transport,
			protocol: Async::HTTP::Protocol::HTTP1,
		)
	end
	
	middleware do
		rack_application = proc do |env|
			body = "Hello World\n"
			
			[
				200,
				{
					"content-type" => "text/plain",
					"content-length" => body.bytesize.to_s
				},
				[body]
			]
		end
		
		Falcon::Server.middleware(rack_application, cache: false)
	end
end

service "supervisor" do
	include Async::Service::Supervisor::Environment
	
	monitors do
		[
			Async::Service::Supervisor::Envoy::Monitor.new(
				bind: xds_bind
			)
		]
	end
end
