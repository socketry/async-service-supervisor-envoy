# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/service/supervisor/envoy/monitor"
require "envoy/config/endpoint/v3/endpoint_pb"

describe Async::Service::Supervisor::Envoy::Monitor do
	Controller = Struct.new(:id, :state)
	
	let(:monitor) {subject.new}
	let(:control_plane) {monitor.control_plane}
	
	def endpoint_assignment(cluster)
		response = control_plane.response(
			Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE,
			[cluster]
		)
		
		Envoy::Config::Endpoint::V3::ClusterLoadAssignment.decode(response.resources.first.value)
	end
	
	it "publishes registered workers as endpoints" do
		controller = Controller.new(1, {
			name: "myservice",
			endpoint: {address: "127.0.0.1", port: 50051}
		})
		
		monitor.register(controller)
		
		assignment = endpoint_assignment("myservice")
		lb_endpoint = assignment.endpoints.first.lb_endpoints.first
		
		expect(assignment.cluster_name).to be == "myservice"
		expect(lb_endpoint.endpoint.address.socket_address.address).to be == "127.0.0.1"
		expect(lb_endpoint.endpoint.address.socket_address.port_value).to be == 50051
	end
	
	it "ignores workers without endpoints" do
		controller = Controller.new(1, {name: "myservice"})
		
		monitor.register(controller)
		
		expect(monitor.as_json).to be == {clusters: {}}
	end
	
	it "removes disconnected workers from endpoints" do
		controller = Controller.new(1, {
			name: "myservice",
			endpoint: {address: "127.0.0.1", port: 50051}
		})
		
		monitor.register(controller)
		monitor.remove(controller)
		
		assignment = endpoint_assignment("myservice")
		
		expect(assignment.endpoints.first.lb_endpoints).to be(:empty?)
	end
	
	it "groups workers by service name" do
		monitor.register(Controller.new(1, {
			name: "service-a",
			endpoint: {address: "127.0.0.1", port: 50051}
		}))
		monitor.register(Controller.new(2, {
			name: "service-b",
			endpoint: {address: "127.0.0.2", port: 50052}
		}))
		
		expect(monitor.as_json[:clusters]).to have_keys("service-a", "service-b")
	end
	
	it "uses health hooks for registered endpoints" do
		monitor = subject.new(health: -> controller{controller.state[:healthy]})
		controller = Controller.new(1, {
			name: "myservice",
			endpoint: {address: "127.0.0.1", port: 50051},
			healthy: false
		})
		
		monitor.register(controller)
		
		response = monitor.control_plane.response(
			Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE,
			["myservice"]
		)
		assignment = Envoy::Config::Endpoint::V3::ClusterLoadAssignment.decode(response.resources.first.value)
		lb_endpoint = assignment.endpoints.first.lb_endpoints.first
		
		expect(lb_endpoint.health_status).to be == :UNHEALTHY
	end
end
