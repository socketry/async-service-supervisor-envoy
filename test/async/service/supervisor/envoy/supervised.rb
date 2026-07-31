# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/service/environment"
require "async/service/supervisor/envoy/supervised"

describe Async::Service::Supervisor::Envoy::Supervised do
	let(:evaluator) do
		base = Module.new do
			def prepare!(...)
			end
		end
		
		Async::Service::Environment.build(base, subject, name: "hello", root: Dir.pwd).evaluator
	end
	
	it "registers concrete endpoint state during worker preparation" do
		instance = Object.new
		evaluator.define_singleton_method(:prepare!) do |*_arguments, **_options|
		end
		listener = Struct.new(:name, :scheme, :protocols, :addresses).new(
			"hello",
			"http",
			["h2", "http/1.1"],
			[Addrinfo.tcp("127.0.0.1", 9292), Addrinfo.unix("/tmp/hello.ipc")]
		)
		state = {
			endpoint: {
				name: "hello",
				scheme: "http",
				protocols: ["h2", "http/1.1"],
				addresses: [
					{address: "127.0.0.1", port: 9292},
					{path: "/tmp/hello.ipc"},
				],
			}
		}
		
		expect(evaluator).to receive(:prepare!).with(instance, state: state)
		
		evaluator.prepare_worker!(instance, listener)
	end
	
	it "rejects unsupported listener addresses" do
		address = Object.new
		address.define_singleton_method(:ip?){false}
		address.define_singleton_method(:unix?){false}
		
		expect do
			evaluator.envoy_address(address)
		end.to raise_exception(ArgumentError)
	end
end
