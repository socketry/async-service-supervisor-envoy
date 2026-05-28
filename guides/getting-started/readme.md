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

## Worker State

Workers are published when they register with `state[:endpoint]`:

``` ruby
state = {
	name: "myservice",
	endpoint: {
		address: "127.0.0.1",
		port: 50051
	}
}
```

Workers without `state[:endpoint]` are ignored by the Envoy monitor.

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
