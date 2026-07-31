# Getting Started

This guide explains how to use `async-service-supervisor-envoy` to publish supervised worker endpoints to Envoy using xDS.

## Installation

Add the gem to your project:

~~~ bash
$ bundle add async-service-supervisor-envoy
~~~

The gem depends on `async-service-supervisor` and `async-grpc-xds`.

## Core Concepts

`async-service-supervisor-envoy` provides:

  - {ruby Async::Service::Supervisor::Envoy::Monitor} - A supervisor monitor that publishes worker endpoints through xDS.
  - {ruby Async::Service::Supervisor::Envoy::Endpoint} - A small value object for endpoint state.

The monitor runs an xDS control plane endpoint. Envoy connects to it using ADS and receives CDS/EDS updates derived from supervisor worker state.

## Endpoint State

Workers are published when they register concrete endpoint state:

``` ruby
state = {
	endpoint: {
		name: "myservice",
		scheme: :http,
		protocols: ["http/1.1"],
		addresses: [
			{address: "127.0.0.1", port: 50051},
			{path: "/run/myservice/worker.ipc"}
		]
	}
}
```

Workers without endpoint state are ignored by the Envoy monitor.

Falcon server workers can register their concrete bound listener automatically:

``` ruby
service "application" do
	include Falcon::Environment::Server
	include Async::Service::Supervisor::Envoy::Supervised
end
```

`Falcon::Environment::Server` reports one listener shared by all of its workers, while `Falcon::Environment::Cluster` reports the listener bound independently by each worker. Falcon describes either bound server resource as a listener. The integration converts that listener into Envoy upstream endpoint state, including its name, scheme, supported protocols, and every concrete IP or Unix socket address.

Addresses belonging to one listener remain grouped as one Envoy load-balancer endpoint. When several workers report the same shared listener, the monitor publishes it once and keeps it available while any reporting worker is healthy.

## Monitor Usage

Add the monitor to your supervisor environment:

``` ruby
require "async/service/supervisor/envoy"

Async::Service::Supervisor::Envoy::Monitor.new(
	bind: "http://127.0.0.1:18000"
)
```

By default, workers are grouped into clusters by `state[:name]`.

## Custom Mapping

You can customize cluster grouping, endpoint selection, and health with a delegate:

``` ruby
class EnvoyDelegate < Async::Service::Supervisor::Envoy::Delegate
	def endpoint_list(supervisor_controller)
		super
	end
	
	def cluster(supervisor_controller, endpoint)
		super
	end
	
	def healthy?(supervisor_controller, endpoint)
		true
	end
end

Async::Service::Supervisor::Envoy::Monitor.new(
	bind: "http://127.0.0.1:18000",
	delegate: EnvoyDelegate.new
)
```

Disconnected workers are removed from EDS. Registered workers that fail the delegate health check remain in EDS with an unhealthy endpoint status.

## Load-aware Balancing

Enable out-of-band ORCA reporting to let Envoy weight independently bound workers using their current processor utilization and request throughput:

``` ruby
utilization_monitor = Async::Service::Supervisor::UtilizationMonitor.new(interval: 1)

[
	utilization_monitor,
	Async::Service::Supervisor::Envoy::Monitor.new(
		bind: "http://0.0.0.0:18000",
		orca: true,
		utilization_monitor: utilization_monitor,
		interval: 1
	)
]
```

The supervisor utilization monitor manages each worker's shared-memory allocation and registration. The Envoy monitor samples it through `sample_by_worker`, combines each worker's `requests_total` counter with processor usage from `process-metrics`, and serves the resulting ORCA reports from the same HTTP/2 endpoint as ADS. It also configures each discovered cluster to use Envoy's client-side weighted-round-robin policy.

The first sample establishes a baseline. Subsequent reports contain normalized `cpu_utilization` and `rps_fractional` values for each worker. Reports are removed immediately when a worker disconnects.

Out-of-band ORCA requires:

  - Envoy 1.39 or later.
  - A fixed TCP port for the monitor's `bind` address.
  - A supervisor utilization monitor registered alongside the Envoy monitor.
  - Independently addressable TCP worker endpoints. Unix sockets and endpoints shared by several workers cannot provide distinct per-worker ORCA identities.

The monitor address and worker addresses must be reachable from Envoy. In a sidecar deployment, binding the monitor to a fixed port in the shared network namespace satisfies this requirement.
