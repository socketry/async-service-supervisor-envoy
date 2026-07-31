# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/service/supervisor/envoy/orca_service"
require "google/protobuf/duration_pb"

describe Async::Service::Supervisor::Envoy::ORCAService do
	it "streams reports for the requested worker authority" do
		report = Xds::Data::Orca::V3::OrcaLoadReport.new(cpu_utilization: 0.5, rps_fractional: 2.0)
		checks = [true, false]
		monitor = Object.new
		monitor.define_singleton_method(:worker?){|authority| authority == "worker-1" && checks.shift}
		monitor.define_singleton_method(:load_report){|authority| report}
		
		request = Xds::Service::Orca::V3::OrcaLoadReportRequest.new(
			report_interval: Google::Protobuf::Duration.new
		)
		input = Object.new
		input.define_singleton_method(:read){request}
		output = []
		output.define_singleton_method(:write){|value| self << value}
		call = Struct.new(:request).new(Struct.new(:authority).new("worker-1"))
		
		subject.new(monitor, minimum_interval: 0).stream_core_metrics(input, output, call)
		
		expect(output).to be == [report]
	end
	
	it "streams an empty report while establishing a baseline" do
		checks = [true, false]
		monitor = Object.new
		monitor.define_singleton_method(:worker?){|authority| authority == "worker-1" && checks.shift}
		monitor.define_singleton_method(:load_report){|authority| nil}
		
		request = Xds::Service::Orca::V3::OrcaLoadReportRequest.new
		input = Object.new
		input.define_singleton_method(:read){request}
		output = []
		output.define_singleton_method(:write){|value| self << value}
		call = Struct.new(:request).new(Struct.new(:authority).new("worker-1"))
		
		subject.new(monitor, minimum_interval: 0).stream_core_metrics(input, output, call)
		
		expect(output).to be == [subject::EMPTY_REPORT]
	end
	
	it "stops when the client closes the stream" do
		monitor = Object.new
		monitor.define_singleton_method(:worker?){|authority| true}
		monitor.define_singleton_method(:load_report){|authority| nil}
		
		input = Object.new
		input.define_singleton_method(:read){Xds::Service::Orca::V3::OrcaLoadReportRequest.new}
		output = Object.new
		output.define_singleton_method(:write){|value| raise Protocol::HTTP::Body::Writable::Closed}
		call = Struct.new(:request).new(Struct.new(:authority).new("worker-1"))
		
		expect do
			subject.new(monitor, minimum_interval: 0).stream_core_metrics(input, output, call)
		end.not.to raise_exception
	end
end
