# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/service/supervisor/envoy/endpoint"

describe Async::Service::Supervisor::Envoy::Endpoint do
	let(:attributes) do
		{
			name: "api",
			scheme: "http",
			protocols: ["h2"],
			addresses: [{path: "/tmp/api.ipc"}],
		}
	end
	
	it "wraps endpoint values" do
		endpoint = subject.wrap(attributes)
		
		expect(endpoint.name).to be == "api"
		expect(endpoint.scheme).to be == :http
		expect(endpoint.protocols).to be == ["h2"]
		expect(endpoint.addresses).to be == [{path: "/tmp/api.ipc"}]
	end
	
	it "returns endpoint instances unchanged" do
		endpoint = subject.new(**attributes)
		
		expect(subject.wrap(endpoint)).to be_equal(endpoint)
	end
	
	it "has immutable value semantics" do
		endpoint = subject.new(**attributes)
		equivalent = subject.new(**attributes)
		
		expect(endpoint).to be == equivalent
		expect(endpoint.eql?(equivalent)).to be == true
		expect(endpoint.hash).to be == equivalent.hash
		expect({endpoint => true}[equivalent]).to be == true
		
		expect(endpoint.frozen?).to be == true
		expect(endpoint.name.frozen?).to be == true
		expect(endpoint.protocols.frozen?).to be == true
		expect(endpoint.protocols.first.frozen?).to be == true
		expect(endpoint.addresses.frozen?).to be == true
		expect(endpoint.addresses.first.frozen?).to be == true
		expect(endpoint.addresses.first[:path].frozen?).to be == true
	end
	
	it "preserves address order in endpoint identity" do
		addresses = [
			{address: "127.0.0.1", port: 9292},
			{path: "/tmp/api.ipc"},
		]
		
		endpoint = subject.new(**attributes, addresses: addresses)
		reordered = subject.new(**attributes, addresses: addresses.reverse)
		
		expect(endpoint).not.to be == reordered
	end
	
	it "rejects invalid endpoint objects" do
		expect do
			subject.wrap(Object.new)
		end.to raise_exception(ArgumentError)
	end
	
	it "rejects endpoints without protocols" do
		expect do
			subject.new(**attributes, protocols: [])
		end.to raise_exception(ArgumentError)
	end
	
	it "rejects invalid endpoint addresses" do
		expect do
			subject.new(**attributes, addresses: [{}])
		end.to raise_exception(ArgumentError)
	end
end
