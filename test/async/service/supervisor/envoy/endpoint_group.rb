# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/service/supervisor/envoy/endpoint_group"
require "async/service/supervisor/envoy/endpoint"

describe Async::Service::Supervisor::Envoy::EndpointGroup do
	Worker = Struct.new(:id)
	
	let(:endpoint) do
		Async::Service::Supervisor::Envoy::Endpoint.build(
			name: "api",
			scheme: "http",
			protocols: ["h2"],
			addresses: [{path: "/tmp/api.ipc"}],
		)
	end
	
	let(:group) {subject.new(endpoint)}
	
	it "tracks workers precisely and aggregates health" do
		first = Worker.new(1)
		second = Worker.new(2)
		
		group.add(first, healthy: false)
		group.add(second, healthy: true)
		
		expect(group.size).to be == 2
		expect(group.healthy?).to be == true
		expect(group.as_json).to be == {
			addresses: [{path: "/tmp/api.ipc"}],
			healthy: true,
		}
		
		group.remove(second)
		
		expect(group.size).to be == 1
		expect(group.healthy?).to be == false
		
		group.remove(first)
		
		expect(group.empty?).to be == true
	end
	
	it "updates an existing worker report by worker ID" do
		group.add(Worker.new(1), healthy: false)
		group.add(Worker.new(1), healthy: true)
		
		expect(group.size).to be == 1
		expect(group.healthy?).to be == true
	end
end
