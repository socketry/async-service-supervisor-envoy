# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/service/supervisor/envoy/monitor"
require "envoy/config/endpoint/v3/endpoint_pb"

describe Async::Service::Supervisor::Envoy::Monitor do
	Controller = Struct.new(:id, :state)
	Endpoint = Struct.new(:address, :port)
	
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
	
	it "refreshes endpoint health on each monitor iteration" do
		controller = Controller.new(1, {
			name: "myservice",
			endpoint: {address: "127.0.0.1", port: 50051},
			healthy: true
		})
		
		monitor = subject.new(health: -> controller{controller.state[:healthy]})
		monitor.register(controller)
		
		controller.state[:healthy] = false
		monitor.run_once
		
		response = monitor.control_plane.response(
			Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE,
			["myservice"]
		)
		assignment = Envoy::Config::Endpoint::V3::ClusterLoadAssignment.decode(response.resources.first.value)
		lb_endpoint = assignment.endpoints.first.lb_endpoints.first
		
		expect(lb_endpoint.health_status).to be == :UNHEALTHY
	end
	
	it "accepts constant cluster, endpoint, and health hooks" do
		endpoint = {address: "127.0.0.1", port: 50051}
		monitor = subject.new(cluster: "myservice", include: endpoint, health: false)
		
		monitor.register(Controller.new(1, {}))
		
		expect(monitor.as_json).to be == {
			clusters: {
				"myservice" => [
					{
						address: "127.0.0.1",
						port: 50051,
						healthy: false
					}
				]
			}
		}
	end
	
	it "wraps endpoint objects" do
		endpoint = Async::Service::Supervisor::Envoy::Endpoint.wrap(
			Endpoint.new("127.0.0.1", 50051)
		)
		
		expect(endpoint.to_h).to be == {
			address: "127.0.0.1",
			port: 50051,
			healthy: true
		}
	end
	
	it "returns endpoint instances unchanged" do
		endpoint = Async::Service::Supervisor::Envoy::Endpoint.new(address: "127.0.0.1", port: 50051)
		
		expect(Async::Service::Supervisor::Envoy::Endpoint.wrap(endpoint)).to be == endpoint
		expect(endpoint).to be(:healthy?)
	end
	
	it "rejects invalid endpoint objects" do
		expect do
			Async::Service::Supervisor::Envoy::Endpoint.wrap(Object.new)
		end.to raise_exception(ArgumentError)
	end
	
	it "runs an xDS server when bound" do
		parent = Class.new do
			def initialize
				@count = 0
			end
			
			def async(&block)
				@count += 1
				
				if @count == 1
					:monitor_task
				else
					block.call
					:server_task
				end
			end
		end.new
		
		calls = []
		original_server = Async::GRPC::XDS.send(:remove_const, :Server)
		
		fake_server = Class.new do
			define_method(:initialize) do |control_plane|
				calls << [:initialize, control_plane]
			end
			
			define_method(:run) do |endpoint|
				calls << [:run, endpoint]
			end
		end
		
		Async::GRPC::XDS.const_set(:Server, fake_server)
		
		monitor = subject.new(bind: "http://127.0.0.1:18000")
		
		expect(monitor.run(parent: parent)).to be == :monitor_task
		expect(calls.first).to be == [:initialize, monitor.control_plane]
		expect(calls.last.last).to be_a(Async::HTTP::Endpoint)
	ensure
		Async::GRPC::XDS.send(:remove_const, :Server)
		Async::GRPC::XDS.const_set(:Server, original_server)
	end
end
