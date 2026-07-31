# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/grpc/service"
require "protocol/http/body/writable"
require "xds/service/orca/v3/open_rca_service"

module Async
	module Service
		module Supervisor
			module Envoy
				# Streams per-worker out-of-band ORCA load reports to Envoy.
				class ORCAService < Async::GRPC::Service
					SERVICE_NAME = "xds.service.orca.v3.OpenRcaService"
					EMPTY_REPORT = Xds::Data::Orca::V3::OrcaLoadReport.new.freeze
					
					# Initialize the ORCA service.
					# @parameter monitor [Monitor] The monitor providing worker load reports.
					# @parameter minimum_interval [Numeric] The minimum reporting interval in seconds.
					def initialize(monitor, minimum_interval: 1)
						super(Xds::Service::Orca::V3::OpenRcaService, SERVICE_NAME)
						
						@monitor = monitor
						@minimum_interval = minimum_interval
					end
					
					# Stream current load reports for the worker named by the request authority.
					# @parameter input [Interface(:read)] The ORCA request stream.
					# @parameter output [Interface(:write)] The ORCA report stream.
					# @parameter call [Protocol::GRPC::Call] The gRPC call context.
					# @asynchronous
					def stream_core_metrics(input, output, call)
						request = input.read
						return unless request
						
						authority = call.request.authority
						interval = [duration(request.report_interval), @minimum_interval].max
						
						while @monitor.worker?(authority)
							output.write(@monitor.load_report(authority) || EMPTY_REPORT)
							
							sleep(interval)
						end
					rescue Protocol::HTTP::Body::Writable::Closed
						# The client closed the reporting stream.
					end
					
					private
					
					def duration(value)
						return 0 unless value
						
						value.seconds + value.nanos.fdiv(1_000_000_000)
					end
				end
			end
		end
	end
end
