# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/service/supervisor/envoy/endpoint_discovery_service"
require "envoy/config/endpoint/v3/endpoint_pb"
require "sus/fixtures/async"

describe Async::Service::Supervisor::Envoy::EndpointDiscoveryService do
	include Sus::Fixtures::Async::ReactorContext
	
	let(:control_plane) {Async::GRPC::XDS::ControlPlane.new}
	let(:service) {subject.new(control_plane)}
	
	# Yields the given requests and then blocks, as a live Envoy stream does:
	def input_for(requests)
		Object.new.tap do |input|
			input.define_singleton_method(:each) do |&block|
				requests.each(&block)
				Async::Task.current.sleep
			end
		end
	end
	
	def output
		[].tap do |output|
			output.define_singleton_method(:write){|value| self << value}
		end
	end
	
	def until_written(output)
		100.times do
			return if output.any?
			Async::Task.current.yield
		end
		
		raise "No response was written!"
	end
	
	def stream(request)
		responses = output
		
		task = Async do
			service.stream_endpoints(input_for([request]), responses, nil)
		end
		
		until_written(responses)
		task.stop
		
		responses.first
	end
	
	def assignment_for(response)
		Envoy::Config::Endpoint::V3::ClusterLoadAssignment.decode(response.resources.first.value)
	end
	
	it "streams the requested assignment" do
		control_plane.update_endpoints("myservice", [
			{addresses: [{address: "127.0.0.1", port: 50051}], healthy: true}
		])
		
		response = stream(Envoy::Service::Discovery::V3::DiscoveryRequest.new(
			type_url: subject::RESOURCE_TYPE,
			resource_names: ["myservice"]
		))
		assignment = assignment_for(response)
		
		expect(response.type_url).to be == subject::RESOURCE_TYPE
		expect(assignment.cluster_name).to be == "myservice"
		expect(assignment.endpoints.first.lb_endpoints.first.endpoint.address.socket_address.port_value).to be == 50051
	end
	
	it "serves a subscriber that omits the implied resource type" do
		control_plane.update_endpoints("myservice", [
			{addresses: [{address: "127.0.0.1", port: 50051}], healthy: true}
		])
		
		response = stream(Envoy::Service::Discovery::V3::DiscoveryRequest.new(resource_names: ["myservice"]))
		
		expect(response.type_url).to be == subject::RESOURCE_TYPE
		expect(assignment_for(response).cluster_name).to be == "myservice"
	end
	
	it "refuses to serve any other resource type" do
		control_plane.update_cluster("myservice")
		control_plane.update_endpoints("myservice", [
			{addresses: [{address: "127.0.0.1", port: 50051}], healthy: true}
		])
		
		response = stream(Envoy::Service::Discovery::V3::DiscoveryRequest.new(
			type_url: Async::GRPC::XDS::ControlPlane::CLUSTER_TYPE,
			resource_names: ["myservice"]
		))
		
		expect(response.type_url).to be == subject::RESOURCE_TYPE
		expect(assignment_for(response).cluster_name).to be == "myservice"
	end
end
