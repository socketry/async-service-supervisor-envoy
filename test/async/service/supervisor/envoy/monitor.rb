# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/service/supervisor/envoy/monitor"
require "async/grpc/xds/http_health_check"
require "envoy/config/endpoint/v3/endpoint_pb"

describe Async::Service::Supervisor::Envoy::Monitor do
	Controller = Struct.new(:id, :state, :process_id)
	
	let(:monitor) {subject.new}
	let(:control_plane) {monitor.control_plane}
	
	def endpoint_assignment(cluster)
		response = control_plane.response(
			Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE,
			[cluster]
		)
		
		Envoy::Config::Endpoint::V3::ClusterLoadAssignment.decode(response.resources.first.value)
	end
	
	def utilization_monitor(samples = [])
		Object.new.tap do |monitor|
			monitor.define_singleton_method(:sample_by_worker){samples.shift || {}}
		end
	end
	
	def processor(samples = [])
		Object.new.tap do |processor|
			processor.define_singleton_method(:sample){|process_ids| samples.shift || {}}
		end
	end
	
	it "publishes registered endpoints" do
		controller = Controller.new(1, {
			endpoint: {name: "myservice", scheme: "http", protocols: ["h2"], addresses: [{address: "127.0.0.1", port: 50051}]}
		})
		
		monitor.register(controller)
		
		assignment = endpoint_assignment("myservice")
		load_balancer_endpoint = assignment.endpoints.first.lb_endpoints.first
		
		expect(assignment.cluster_name).to be == "myservice"
		expect(load_balancer_endpoint.endpoint.address.socket_address.address).to be == "127.0.0.1"
		expect(load_balancer_endpoint.endpoint.address.socket_address.port_value).to be == 50051
	end
	
	it "publishes active health checks" do
		health_check = Async::GRPC::XDS::HTTPHealthCheck.build("/services/ping")
		monitor = subject.new(health_checks: [health_check])
		controller = Controller.new(1, {
			endpoint: {name: "myservice", scheme: "http", protocols: ["h2"], addresses: [{address: "127.0.0.1", port: 50051}]}
		})
		
		monitor.register(controller)
		cluster = monitor.control_plane.resources(Async::GRPC::XDS::ControlPlane::CLUSTER_TYPE).first
		
		expect(cluster.health_checks).to be == [health_check]
	end
	
	it "publishes ORCA worker identity and load-balancing configuration" do
		monitor = subject.new(
			bind: "http://127.0.0.1:18000",
			orca: true,
			processor: processor,
			utilization_monitor: utilization_monitor
		)
		controller = Controller.new(1, {
			endpoint: {name: "myservice", scheme: "http", protocols: ["h2"], addresses: [{address: "127.0.0.1", port: 50051}]}
		}, 123)
		
		monitor.register(controller)
		
		response = monitor.control_plane.response(
			Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE,
			["myservice"]
		)
		assignment = Envoy::Config::Endpoint::V3::ClusterLoadAssignment.decode(response.resources.first.value)
		cluster = monitor.control_plane.resources(Async::GRPC::XDS::ControlPlane::CLUSTER_TYPE).first
		typed_configuration = cluster.load_balancing_policy.policies.first.typed_extension_config
		configuration = Envoy::Extensions::LoadBalancingPolicies::ClientSideWeightedRoundRobin::V3::ClientSideWeightedRoundRobin.decode(
			typed_configuration.typed_config.value
		)
		
		expect(assignment.endpoints.first.lb_endpoints.first.endpoint.hostname).to be == "worker-1"
		expect(configuration.enable_oob_load_report.value).to be == true
		expect(configuration.oob_reporting_config.port_value).to be == 18000
	end
	
	it "samples per-worker ORCA load reports" do
		utilization = utilization_monitor([
			{1 => {state: {}, utilization: {requests_total: 10}}},
			{1 => {state: {}, utilization: {requests_total: 14}}},
		])
		processor_sample = Struct.new(:duration, :utilization).new(2.0, 0.5)
		processor = processor([
			{},
			{123 => processor_sample},
		])
		monitor = subject.new(
			bind: "http://127.0.0.1:18000",
			orca: true,
			processor: processor,
			utilization_monitor: utilization
		)
		controller = Controller.new(1, {
			endpoint: {name: "myservice", scheme: "http", protocols: ["h2"], addresses: [{address: "127.0.0.1", port: 50051}]}
		}, 123)
		
		monitor.register(controller)
		monitor.run_once
		expect(monitor.load_report("worker-1")).to be_nil
		
		monitor.run_once
		report = monitor.load_report("worker-1")
		
		expect(report.cpu_utilization).to be == 0.5
		expect(report.rps_fractional).to be == 2.0
		expect(report.named_metrics).to be == {"orca.heartbeat" => 0.0}
		expect(monitor.worker?("worker-1")).to be == true
		
		monitor.remove(controller)
		expect(monitor.worker?("worker-1")).to be == false
		expect(monitor.load_report("worker-1")).to be_nil
	end
	
	it "requires a fixed bind address for ORCA" do
		expect do
			subject.new(orca: true)
		end.to raise_exception(ArgumentError)
	end
	
	it "requires a utilization monitor for ORCA" do
		expect do
			subject.new(bind: "http://127.0.0.1:18000", orca: true)
		end.to raise_exception(ArgumentError)
	end
	
	it "rejects Unix endpoints for out-of-band ORCA" do
		monitor = subject.new(
			bind: "http://127.0.0.1:18000",
			orca: true,
			processor: processor,
			utilization_monitor: utilization_monitor
		)
		
		expect do
			monitor.register(Controller.new(1, {
				endpoint: {name: "myservice", scheme: "http", protocols: ["h2"], addresses: [{path: "/tmp/falcon.ipc"}]}
			}, 123))
		end.to raise_exception(ArgumentError)
	end
	
	it "publishes a supervised Unix endpoint" do
		controller = Controller.new(1, {
			endpoint: {
				name: "myservice",
				scheme: "http",
				protocols: ["http/1.1"],
				addresses: [{path: "/tmp/falcon.ipc"}],
			}
		})
		
		monitor.register(controller)
		
		assignment = endpoint_assignment("myservice")
		load_balancer_endpoint = assignment.endpoints.first.lb_endpoints.first
		
		expect(load_balancer_endpoint.endpoint.address.pipe.path).to be == "/tmp/falcon.ipc"
		
		cluster = control_plane.resources(Async::GRPC::XDS::ControlPlane::CLUSTER_TYPE).first
		expect(cluster.http2_protocol_options).to be_nil
	end
	
	it "keeps one endpoint's addresses grouped" do
		controller = Controller.new(1, {
			endpoint: {
				name: "myservice",
				scheme: "http",
				protocols: ["h2"],
				addresses: [
					{address: "127.0.0.1", port: 9292},
					{path: "/tmp/falcon.ipc"},
				],
			}
		})
		
		monitor.register(controller)
		
		assignment = endpoint_assignment("myservice")
		endpoints = assignment.endpoints.first.lb_endpoints
		
		expect(endpoints.size).to be == 1
		expect(endpoints.first.endpoint.additional_addresses.first.address.pipe.path).to be == "/tmp/falcon.ipc"
	end
	
	it "ignores workers without endpoints" do
		controller = Controller.new(1, {name: "myservice"})
		
		monitor.register(controller)
		
		expect(monitor.as_json).to be == {clusters: {}}
	end
	
	it "removes disconnected workers from endpoints" do
		controller = Controller.new(1, {
			endpoint: {name: "myservice", scheme: "http", protocols: ["h2"], addresses: [{address: "127.0.0.1", port: 50051}]}
		})
		
		monitor.register(controller)
		monitor.remove(controller)
		
		assignment = endpoint_assignment("myservice")
		
		expect(assignment.endpoints.first.lb_endpoints).to be(:empty?)
	end
	
	it "publishes a shared listener once while any worker remains" do
		delegate = Class.new(Async::Service::Supervisor::Envoy::Delegate) do
			def healthy?(supervisor_controller, endpoint)
				supervisor_controller.state[:healthy]
			end
		end.new
		
		monitor = subject.new(delegate: delegate)
		endpoint = {name: "myservice", scheme: "http", protocols: ["h2"], addresses: [{address: "127.0.0.1", port: 50051}]}
		first = Controller.new(1, {endpoint: endpoint, healthy: false})
		second = Controller.new(2, {endpoint: endpoint, healthy: true})
		
		monitor.register(first)
		monitor.register(second)
		
		expect(monitor.as_json[:clusters]["myservice"]).to be == [
			{addresses: [{address: "127.0.0.1", port: 50051}], healthy: true}
		]
		
		monitor.remove(second)
		
		expect(monitor.as_json[:clusters]["myservice"]).to be == [
			{addresses: [{address: "127.0.0.1", port: 50051}], healthy: false}
		]
		
		monitor.remove(first)
		
		expect(monitor.as_json[:clusters]["myservice"]).to be == nil
	end
	
	it "groups workers by service name" do
		monitor.register(Controller.new(1, {
			endpoint: {name: "service-a", scheme: "http", protocols: ["h2"], addresses: [{address: "127.0.0.1", port: 50051}]}
		}))
		monitor.register(Controller.new(2, {
			endpoint: {name: "service-b", scheme: "http", protocols: ["h2"], addresses: [{address: "127.0.0.2", port: 50052}]}
		}))
		
		expect(monitor.as_json[:clusters]).to have_keys("service-a", "service-b")
	end
	
	it "publishes multiple endpoints from one worker" do
		monitor.register(Controller.new(1, {
			endpoints: [
				{name: "api-http1", scheme: "http", protocols: ["http/1.1"], addresses: [{address: "127.0.0.1", port: 50050}]},
				{name: "api-http2", scheme: "http", protocols: ["h2"], addresses: [{address: "127.0.0.1", port: 50051}]}
			]
		}))
		
		expect(monitor.as_json).to be == {
			clusters: {
				"api-http1" => [
					{
						addresses: [{address: "127.0.0.1", port: 50050}],
						healthy: true
					}
				],
				"api-http2" => [
					{
						addresses: [{address: "127.0.0.1", port: 50051}],
						healthy: true
					}
				]
			}
		}
	end
	
	it "updates published endpoints from controller state" do
		controller = Controller.new(1, {
			endpoint: {name: "myservice", scheme: "http", protocols: ["h2"], addresses: [{address: "127.0.0.1", port: 50051}]}
		})
		
		monitor.register(controller)
		
		controller.state[:endpoint] = {name: "myservice", scheme: "http", protocols: ["h2"], addresses: [{address: "127.0.0.2", port: 50052}]}
		monitor.run_once
		
		assignment = endpoint_assignment("myservice")
		load_balancer_endpoint = assignment.endpoints.first.lb_endpoints.first
		
		expect(load_balancer_endpoint.endpoint.address.socket_address.address).to be == "127.0.0.2"
		expect(load_balancer_endpoint.endpoint.address.socket_address.port_value).to be == 50052
	end
	
	it "uses the delegate for endpoint health" do
		delegate = Class.new(Async::Service::Supervisor::Envoy::Delegate) do
			def healthy?(supervisor_controller, endpoint)
				supervisor_controller.state[:healthy]
			end
		end.new
		
		monitor = subject.new(delegate: delegate)
		controller = Controller.new(1, {
			endpoint: {name: "myservice", scheme: "http", protocols: ["h2"], addresses: [{address: "127.0.0.1", port: 50051}]},
			healthy: false
		})
		
		monitor.register(controller)
		
		response = monitor.control_plane.response(
			Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE,
			["myservice"]
		)
		assignment = Envoy::Config::Endpoint::V3::ClusterLoadAssignment.decode(response.resources.first.value)
		load_balancer_endpoint = assignment.endpoints.first.lb_endpoints.first
		
		expect(load_balancer_endpoint.health_status).to be == :UNHEALTHY
	end
	
	it "refreshes endpoint health on each monitor iteration" do
		delegate = Class.new(Async::Service::Supervisor::Envoy::Delegate) do
			def healthy?(supervisor_controller, endpoint)
				supervisor_controller.state[:healthy]
			end
		end.new
		
		controller = Controller.new(1, {
			endpoint: {name: "myservice", scheme: "http", protocols: ["h2"], addresses: [{address: "127.0.0.1", port: 50051}]},
			healthy: true
		})
		
		monitor = subject.new(delegate: delegate)
		monitor.register(controller)
		
		controller.state[:healthy] = false
		monitor.run_once
		
		response = monitor.control_plane.response(
			Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE,
			["myservice"]
		)
		assignment = Envoy::Config::Endpoint::V3::ClusterLoadAssignment.decode(response.resources.first.value)
		load_balancer_endpoint = assignment.endpoints.first.lb_endpoints.first
		
		expect(load_balancer_endpoint.health_status).to be == :UNHEALTHY
	end
	
	it "uses the delegate to customize cluster and health" do
		delegate = Class.new(Async::Service::Supervisor::Envoy::Delegate) do
			def endpoint_list(supervisor_controller)
				[
					Async::Service::Supervisor::Envoy::Endpoint.build(
						name: "ignored",
						scheme: "http",
						protocols: ["http/1.1"],
						addresses: [{address: "127.0.0.1", port: 50051}]
					)
				]
			end
			
			def cluster(supervisor_controller, endpoint)
				"myservice"
			end
			
			def healthy?(supervisor_controller, endpoint)
				false
			end
		end.new
		
		monitor = subject.new(delegate: delegate)
		
		monitor.register(Controller.new(1, {}))
		
		expect(monitor.as_json).to be == {
			clusters: {
				"myservice" => [
					{
						addresses: [{address: "127.0.0.1", port: 50051}],
						healthy: false
					}
				]
			}
		}
	end
	
	it "selects the preferred common endpoint protocol" do
		monitor.register(Controller.new(1, {
			endpoint: {name: "myservice", scheme: "http", protocols: ["h2", "http/1.1"], addresses: [{path: "/tmp/one.ipc"}]}
		}))
		monitor.register(Controller.new(2, {
			endpoint: {name: "myservice", scheme: "http", protocols: ["h2"], addresses: [{path: "/tmp/two.ipc"}]}
		}))
		
		cluster = control_plane.resources(Async::GRPC::XDS::ControlPlane::CLUSTER_TYPE).first
		expect(cluster.http2_protocol_options).not.to be_nil
	end
	
	it "rejects endpoints without a common protocol in one cluster" do
		monitor.register(Controller.new(1, {
			endpoint: {name: "myservice", scheme: "http", protocols: ["http/1.1"], addresses: [{path: "/tmp/one.ipc"}]}
		}))
		
		expect do
			monitor.register(Controller.new(2, {
				endpoint: {name: "myservice", scheme: "http", protocols: ["h2"], addresses: [{path: "/tmp/two.ipc"}]}
			}))
		end.to raise_exception(ArgumentError)
	end
	
	it "rejects unsupported endpoint protocols" do
		expect do
			monitor.register(Controller.new(1, {
				endpoint: {name: "myservice", scheme: "http", protocols: ["unsupported"], addresses: [{path: "/tmp/one.ipc"}]}
			}))
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
