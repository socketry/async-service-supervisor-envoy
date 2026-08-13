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
				if result = yield
					return result
				end
			rescue => error
			end
			
			sleep interval
		end
		
		raise error || "Condition was not met within #{timeout} seconds!"
	end
	
	def find_hash(value, &block)
		case value
		when Hash
			return value if yield(value)
			
			value.each_value do |child|
				if match = find_hash(child, &block)
					return match
				end
			end
		when Array
			value.each do |child|
				if match = find_hash(child, &block)
					return match
				end
			end
		end
	end
	
	it "routes requests through Envoy to supervised Falcon workers" do
		uri = envoy_uri
		
		responses = eventually do
			responses = 20.times.map{Net::HTTP.get_response(uri)}
			backend_ids = responses.filter_map{|response| response["x-backend-id"]}.uniq.sort
			
			responses if backend_ids == ["backend-a", "backend-b"]
		end
		
		responses.each do |response|
			expect(response.code.to_i).to be == 200
			expect(response.body).to be =~ /Hello from backend-[ab]/
		end
		
		expect(responses.filter_map{|response| response["x-backend-id"]}.uniq.sort).to be == ["backend-a", "backend-b"]
	end
	
	it "discovers cluster endpoints from the supervisor monitor" do
		uri = admin_uri + "/clusters?format=json"
		
		host_statuses = eventually do
			if (response = Net::HTTP.get_response(uri)).code.to_i == 200
				clusters = JSON.parse(response.body)
				cluster_status = clusters.fetch("cluster_statuses").find do |cluster|
					cluster.fetch("name") == "app-http1"
				end
				
				hosts = cluster_status&.fetch("host_statuses", nil)
				hosts if hosts&.size == 2
			end
		end
		
		addresses = host_statuses.map do |host|
			host.fetch("address").fetch("socket_address").fetch("port_value")
		end
		
		expect(addresses.sort).to be == [9292, 9293]
	end
	
	if ENV.fetch("ORCA", "false") == "true"
		it "reports ORCA load-balancing policy to Envoy" do
			uri = admin_uri + "/config_dump"
			
			cluster = eventually do
				if (response = Net::HTTP.get_response(uri)).code.to_i == 200
					config_dump = JSON.parse(response.body)
					clusters_config = config_dump.fetch("configs").find do |config|
						config["@type"]&.end_with?("envoy.admin.v3.ClustersConfigDump")
					end
					dynamic_clusters = clusters_config.fetch("dynamic_active_clusters", [])
					cluster = dynamic_clusters.filter_map{|entry| entry["cluster"]}.find{|cluster| cluster["name"] == "app-http1"}
					
					if cluster
						cluster_json = JSON.generate(cluster)
						cluster if cluster_json.include?("client_side_weighted_round_robin") || cluster_json.include?("ClientSideWeightedRoundRobin")
					end
				end
			end
			
			typed_extension_config = cluster.fetch("load_balancing_policy").fetch("policies").first.fetch("typed_extension_config")
			typed_config = typed_extension_config.fetch("typed_config")
			
			expect(typed_extension_config.fetch("name")).to be == "envoy.load_balancing_policies.client_side_weighted_round_robin"
			expect(typed_config.fetch("@type")).to be == "type.googleapis.com/envoy.extensions.load_balancing_policies.client_side_weighted_round_robin.v3.ClientSideWeightedRoundRobin"
			expect(typed_config.fetch("enable_oob_load_report")).to be == true
			expect(typed_config.fetch("oob_reporting_period")).to be == "1s"
		end
	end
end
