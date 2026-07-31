# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/http/endpoint"
require "async/service/supervisor/monitor"
require "async/service/supervisor/utilization_monitor"
require "async/grpc/xds/client_side_weighted_round_robin"
require "async/grpc/xds/control_plane"
require "async/grpc/xds/server"
require "process/metrics"
require "xds/data/orca/v3/orca_load_report_pb"

require_relative "delegate"
require_relative "endpoint"
require_relative "endpoint_group"
require_relative "orca_service"

module Async
	module Service
		module Supervisor
			# Provides Envoy integration for supervisor-managed services.
			module Envoy
				# Represents a supervisor monitor that publishes worker endpoints to Envoy using xDS.
				class Monitor < Async::Service::Supervisor::Monitor
					# Initialize the monitor.
					# @parameter bind [String | Nil] The optional address for the xDS control plane server.
					# @parameter delegate [Delegate] The delegate used to map supervisor state into Envoy endpoints.
					# @parameter control_plane [Async::GRPC::XDS::ControlPlane] The xDS control plane to update.
					# @parameter orca [Boolean] Whether to collect and serve per-worker ORCA load reports.
					# @parameter processor [Process::Metrics::Processor | Nil] The optional process CPU sampler.
					# @parameter utilization_monitor [Async::Service::Supervisor::UtilizationMonitor | Nil] The optional per-worker utilization monitor.
					# @parameter interval [Numeric] The endpoint reconciliation and ORCA reporting interval in seconds.
					def initialize(
						bind: nil,
						delegate: Delegate.new,
						control_plane: Async::GRPC::XDS::ControlPlane.new,
						orca: false,
						processor: nil,
						utilization_monitor: nil,
						interval: 1,
						**options
					)
						super(interval: interval, **options)
						
						@bind = bind
						@delegate = delegate
						@control_plane = control_plane
						@interval = interval
						@orca = orca
						@controllers = {}
						@published_clusters = {}
						@server_task = nil
						@mutex = Mutex.new
						
						if @orca
							raise ArgumentError, "ORCA reporting requires a TCP bind address!" unless @bind
							
							@orca_port = server_endpoint.url.port
							raise ArgumentError, "ORCA reporting requires a fixed TCP port!" unless @orca_port&.positive?
							
							@processor = processor || Process::Metrics::Processor.new
							@utilization_monitor = utilization_monitor || Async::Service::Supervisor::UtilizationMonitor.new(interval: interval)
							@request_totals = {}
							@load_reports = {}
							@authorities = {}
						end
					end
					
					# @attribute [Async::GRPC::XDS::ControlPlane] The xDS control plane receiving cluster and endpoint updates.
					attr :control_plane
					
					# @attribute [Delegate] The delegate used to map supervisor state into Envoy endpoints.
					attr :delegate
					
					# Register a supervisor worker with Envoy.
					# @parameter supervisor_controller [Object] The supervisor controller describing the worker.
					# @returns [void]
					def register(supervisor_controller)
						@utilization_monitor&.register(supervisor_controller)
						
						@mutex.synchronize do
							@controllers[supervisor_controller.id] = supervisor_controller
							@authorities[worker_hostname(supervisor_controller)] = supervisor_controller.id if @orca
							reconcile
						end
					end
					
					# Remove a supervisor worker from Envoy.
					# @parameter supervisor_controller [Object] The supervisor controller describing the worker.
					# @returns [void]
					def remove(supervisor_controller)
						@mutex.synchronize do
							@controllers.delete(supervisor_controller.id)
							if @orca
								hostname = worker_hostname(supervisor_controller)
								@authorities.delete(hostname)
								@load_reports.delete(hostname)
								@request_totals.delete(supervisor_controller.id)
							end
							reconcile
						end
						
						@utilization_monitor&.remove(supervisor_controller)
					end
					
					# Run the monitor and optional xDS server task.
					# @parameter parent [Async::Task] The parent task used for the xDS server.
					# @returns [Async::Task] The monitor task.
					def run(parent: Async::Task.current)
						task = super(parent: parent)
						
						if @bind
							@server_task = parent.async do
								server = Async::GRPC::XDS::Server.new(@control_plane)
								server.dispatcher.register(ORCAService.new(self, minimum_interval: @interval)) if @orca
								server.run(server_endpoint)
							end
						end
						
						task
					end
					
					# Convert the currently published endpoints to JSON-compatible data.
					# @returns [Hash] The clusters and endpoint hashes.
					def as_json
						@mutex.synchronize do
							{
								clusters: build_clusters
							}
						end
					end
					
					# Determine whether an ORCA worker authority is currently registered.
					# @parameter authority [String] The gRPC request authority.
					# @returns [Boolean] Whether the authority identifies a live worker.
					def worker?(authority)
						return false unless @orca
						
						@mutex.synchronize{@authorities.key?(authority)}
					end
					
					# Get the latest ORCA report for a worker authority.
					# @parameter authority [String] The gRPC request authority.
					# @returns [Xds::Data::Orca::V3::OrcaLoadReport | Nil] The latest valid report, if available.
					def load_report(authority)
						return unless @orca
						
						@mutex.synchronize{@load_reports[authority]}
					end
					
					# Refresh endpoint health and publish updated EDS state.
					# @returns [void]
					def run_once
						sample_load_reports if @orca
						
						@mutex.synchronize do
							reconcile
						end
					end
					
					private
					
					def server_endpoint
						@server_endpoint ||= Async::HTTP::Endpoint.parse(@bind, protocol: Async::HTTP::Protocol::HTTP2)
					end
					
					def worker_hostname(supervisor_controller)
						"worker-#{supervisor_controller.id}"
					end
					
					def build_record(supervisor_controller, endpoint)
						cluster = @delegate.cluster(supervisor_controller, endpoint)
						return unless cluster
						
						{
							cluster: cluster.to_s,
							endpoint: endpoint,
							worker: supervisor_controller,
							healthy: @delegate.healthy?(supervisor_controller, endpoint),
						}
					end
					
					def build_records(supervisor_controller)
						@delegate.endpoint_list(supervisor_controller).filter_map do |endpoint|
							build_record(supervisor_controller, endpoint)
						end
					end
					
					def reconcile
						records_by_cluster = build_records_by_cluster
						clusters = build_clusters(records_by_cluster)
						
						records_by_cluster.each do |cluster, records|
							configuration = cluster_configuration(records)
							
							unless @published_clusters[cluster] == configuration
								@control_plane.update_cluster(cluster, **configuration)
								@published_clusters[cluster] = configuration
							end
						end
						
						(@published_clusters.keys | clusters.keys).each do |cluster|
							@control_plane.update_endpoints(cluster, clusters.fetch(cluster, []))
						end
					end
					
					def build_records_by_cluster
						@controllers.each_value.flat_map do |controller|
							build_records(controller)
						end.group_by do |record|
							record[:cluster]
						end
					end
					
					def build_clusters(records_by_cluster = build_records_by_cluster)
						records_by_cluster.transform_values do |records|
							if @orca
								records.map do |record|
									{
										addresses: record[:endpoint].addresses,
										healthy: record[:healthy],
										hostname: worker_hostname(record[:worker]),
									}
								end
							else
								groups = {}
								
								records.each do |record|
									group = groups[record[:endpoint]] ||= EndpointGroup.new(record[:endpoint])
									group.add(record[:worker], healthy: record[:healthy])
								end
								
								groups.each_value.map(&:as_json)
							end
						end
					end
					
					def cluster_configuration(records)
						schemes = records.map{|record| record[:endpoint].scheme}.uniq
						protocols = records.map{|record| record[:endpoint].protocols}
						common_protocols = protocols.reduce{|common, names| common & names}
						
						raise ArgumentError, "Envoy cluster contains incompatible schemes: #{schemes.inspect}" if schemes.size > 1
						raise ArgumentError, "Envoy cluster contains no common protocols: #{protocols.inspect}" if common_protocols.empty?
						raise ArgumentError, "HTTPS upstream endpoints are not yet supported!" if schemes.first == :https
						
						configuration = {protocol: envoy_protocol(common_protocols)}
						
						if @orca
							if records.any?{|record| record[:endpoint].addresses.any?{|address| address[:path]}}
								raise ArgumentError, "Out-of-band ORCA reporting requires IP endpoints!"
							end
							
							configuration[:load_balancing_policy] = Async::GRPC::XDS::ClientSideWeightedRoundRobin.build(
								@orca_port,
								reporting_period: @interval
							)
						end
						
						configuration
					end
					
					def sample_load_reports
						controllers = @mutex.synchronize{@controllers.dup}
						workers = @utilization_monitor.sample_by_worker
						process_ids = controllers.each_value.filter_map(&:process_id)
						processor_samples = @processor.sample(process_ids)
						request_totals = {}
						
						workers.each do |worker_id, worker|
							requests_total = worker[:utilization][:requests_total]
							if requests_total.is_a?(Numeric) && requests_total.finite?
								request_totals[worker_id] = requests_total
							end
						end
						
						@mutex.synchronize do
							controllers.each do |worker_id, controller|
								next unless @controllers[worker_id].equal?(controller)
								
								hostname = worker_hostname(controller)
								processor_sample = processor_samples[controller.process_id]
								requests_total = request_totals[worker_id]
								previous_requests_total = @request_totals[worker_id]
								
								if processor_sample && requests_total && previous_requests_total && requests_total >= previous_requests_total
									rps = (requests_total - previous_requests_total).fdiv(processor_sample.duration)
									cpu = processor_sample.utilization
									
									if rps.finite? && cpu.finite?
										@load_reports[hostname] = Xds::Data::Orca::V3::OrcaLoadReport.new(
											cpu_utilization: cpu,
											rps_fractional: rps,
											named_metrics: {"orca.heartbeat" => 0.0},
										)
										next
									end
								end
								
								@load_reports.delete(hostname)
							end
							
							@request_totals = request_totals
							
							Console.debug(self, "Sampled ORCA load reports.",
								workers: workers.keys,
								processes: processor_samples.keys,
								requests: request_totals,
								reports: @load_reports.keys,
							)
						end
					end
					
					def envoy_protocol(protocols)
						protocols.each do |protocol|
							case protocol
							when "h2"
								return :http2
							when "http/1.1", "http/1.0"
								return :http1
							end
						end
						
						raise ArgumentError, "Envoy cluster contains no supported protocols: #{protocols.inspect}"
					end
				end
			end
		end
	end
end
