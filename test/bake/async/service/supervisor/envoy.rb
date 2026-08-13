# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "bake/context"

describe "async:service:supervisor:envoy" do
	let(:context) {Bake::Context.load}
	let(:status) do
		[
			{type: "Other::Monitor", data: {}},
			{
				type: "Async::Service::Supervisor::Envoy::Monitor",
				data: {
					clusters: {
						"api" => [
							{addresses: [{path: "/tmp/api.ipc"}], healthy: true}
						]
					},
					orca: {
						port: 18000,
						authorities: {"worker-1" => 1},
						reports: {
							"worker-1" => {
								cpu_utilization: 0.5,
								rps_fractional: 2.0,
								named_metrics: {"orca.heartbeat" => 0.0}
							}
						}
					}
				}
			}
		]
	end
	
	def invoke(name, status: self.status)
		result = nil
		supervisor_status = Object.new
		supervisor_status.define_singleton_method(:call){status}
		
		mock(context) do |mock|
			mock.replace(:[]) do |name|
				expect(name).to be == "async:service:supervisor:status"
				supervisor_status
			end
			
			result = context.lookup("async:service:supervisor:envoy:#{name}").call
		end
		
		result
	end
	
	it "returns the Envoy monitor status" do
		expect(invoke("status")).to be == {
			type: "Async::Service::Supervisor::Envoy::Monitor",
			data: {
				clusters: {
					"api" => [
						{addresses: [{path: "/tmp/api.ipc"}], healthy: true}
					]
				},
				orca: {
					port: 18000,
					authorities: {"worker-1" => 1},
					reports: {
						"worker-1" => {
							cpu_utilization: 0.5,
							rps_fractional: 2.0,
							named_metrics: {"orca.heartbeat" => 0.0}
						}
					}
				}
			}
		}
	end
	
	it "returns the published clusters" do
		expect(invoke("clusters")).to be == {
			"api" => [
				{addresses: [{path: "/tmp/api.ipc"}], healthy: true}
			]
		}
	end
	
	it "returns a flattened endpoint list" do
		expect(invoke("endpoints")).to be == [
			{
				addresses: [{path: "/tmp/api.ipc"}],
				healthy: true,
				cluster: "api"
			}
		]
	end
	
	it "returns ORCA load reports" do
		expect(invoke("orca")).to be == {
			port: 18000,
			authorities: {"worker-1" => 1},
			reports: {
				"worker-1" => {
					cpu_utilization: 0.5,
					rps_fractional: 2.0,
					named_metrics: {"orca.heartbeat" => 0.0}
				}
			}
		}
	end
	
	it "fails when the Envoy monitor is not running" do
		expect do
			invoke("status", status: [])
		end.to raise_exception(RuntimeError, message: be =~ /no .*envoy.*monitor/i)
	end
	
	it "fails when ORCA reporting is not configured" do
		status = [
			{
				type: "Async::Service::Supervisor::Envoy::Monitor",
				data: {
					clusters: {}
				}
			}
		]
		
		expect do
			invoke("orca", status: status)
		end.to raise_exception(RuntimeError, message: be =~ /ORCA reporting/)
	end
end
