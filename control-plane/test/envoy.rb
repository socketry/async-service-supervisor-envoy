# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "json"
require "net/http"
require "uri"

describe "Envoy control plane" do
	let(:envoy_uri) {URI(ENV.fetch("ENVOY_URI"))}
	let(:admin_uri) {URI(ENV.fetch("ENVOY_ADMIN_URI"))}
	
	def eventually(timeout: 20, interval: 0.5)
		deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
		error = nil
		
		while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
			begin
				return yield
			rescue => error
				sleep interval
			end
		end
		
		raise error
	end
	
	it "routes requests through Envoy to supervised Falcon workers" do
		uri = envoy_uri
		
		backend_ids = eventually do
			20.times.map do
				response = Net::HTTP.get_response(uri)
				
				expect(response.code.to_i).to be == 200
				expect(response.body).to be =~ /Hello from backend-[ab]/
				
				response["x-backend-id"]
			end
		end
		
		expect(backend_ids.compact.uniq.sort).to be == ["backend-a", "backend-b"]
	end
	
	it "loads the xDS cluster from the supervisor monitor" do
		uri = admin_uri + "/clusters?format=json"
		
		cluster_status = eventually do
			response = Net::HTTP.get_response(uri)
			
			expect(response.code.to_i).to be == 200
			
			clusters = JSON.parse(response.body)
			clusters.fetch("cluster_statuses").find do |cluster|
				cluster.fetch("name") == "app-http1"
			end
		end
		
		expect(cluster_status).not.to be_nil
	end
end
