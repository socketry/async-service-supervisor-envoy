# Async::Service::Supervisor::Envoy

Provides an Envoy xDS monitor for `async-service-supervisor`.

[![Development Status](https://github.com/socketry/async-service-supervisor-envoy/workflows/Test/badge.svg)](https://github.com/socketry/async-service-supervisor-envoy/actions?workflow=Test)

## Features

`async-service-supervisor-envoy` publishes supervised worker endpoints to Envoy:

  - **xDS control plane** - Runs an ADS server backed by `async-grpc-xds`.
  - **Supervisor integration** - Registers and removes endpoints from supervisor worker lifecycle events.
  - **Multiple clusters** - Groups workers by `state[:name]` by default.
  - **Endpoint contract** - Publishes workers with `state[:endpoint]` and ignores workers without endpoints.
  - **Delegate mapping** - Uses a delegate object for endpoint selection, cluster grouping, and health without active probing.

## Usage

Please see the [project documentation](https://socketry.github.io/async-service-supervisor-envoy/) for more details.

  - [Getting Started](https://socketry.github.io/async-service-supervisor-envoy/guides/getting-started/index) - This guide explains how to use `async-service-supervisor-envoy` to publish supervised worker endpoints to Envoy using xDS.

## Releases

Please see the [project releases](https://socketry.github.io/async-service-supervisor-envoy/releases/index) for all releases.

### v0.1.0

  - Initial release.

## See Also

  - [async-service-supervisor](https://github.com/socketry/async-service-supervisor) - Supervisor for managed Async service workers.
  - [async-grpc-xds](https://github.com/socketry/async-grpc-xds) - xDS support for Async::GRPC.
  - [Envoy xDS](https://www.envoyproxy.io/docs/envoy/latest/api-docs/xds_protocol) - Envoy dynamic configuration protocol.

## Contributing

We welcome contributions to this project.

1.  Fork it.
2.  Create your feature branch (`git checkout -b my-new-feature`).
3.  Commit your changes (`git commit -am 'Add some feature'`).
4.  Push to the branch (`git push origin my-new-feature`).
5.  Create new Pull Request.

### Running Tests

To run the test suite:

``` shell
bundle exec sus
```

### Making Releases

To make a new release:

``` shell
bundle exec bake gem:release:patch # or minor or major
```

### Developer Certificate of Origin

In order to protect users of this project, we require all contributors to comply with the [Developer Certificate of Origin](https://developercertificate.org/). This ensures that all contributions are properly licensed and attributed.

### Community Guidelines

This project is best served by a collaborative and respectful environment. Treat each other professionally, respect differing viewpoints, and engage constructively. Harassment, discrimination, or harmful behavior is not tolerated. Communicate clearly, listen actively, and support one another. If any issues arise, please inform the project maintainers.
