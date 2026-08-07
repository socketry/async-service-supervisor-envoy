# Control Plane Testing

This scenario exercises both supported Envoy control plane topologies:

- Falcon workers register with `Async::Service::Supervisor::Worker`.
- Each worker publishes `state[:endpoint]` with its name, scheme, supported protocols, and concrete addresses.
- `Async::Service::Supervisor::Envoy::Monitor` maps supervisor state into Envoy endpoint assignments.
- Envoy connects to the supervisor's dedicated discovery services.
- Envoy routes HTTP traffic to the supervised Falcon workers.

The default configuration enables cluster publication. Only the management cluster is declared statically in `envoy.yaml`; the application cluster is discovered through CDS and its workers are discovered through EDS.

The EDS-only configuration disables cluster publication. Both the management and application clusters are declared statically in `envoy-eds.yaml`, while the application's workers are still discovered through EDS. This represents a deployment where bootstrap configuration or another control plane owns clusters.

Envoy initiates the connection. The supervisor does not call Envoy's admin API or mutate Envoy directly. Once Envoy has connected and subscribed, the supervisor streams updates over that connection. This matches the normal xDS control plane model and gives Envoy ownership of reconnects, resource ACK/NACK handling, and sidecar lifecycle.

## Running Tests

``` bash
$ docker compose -f control-plane/docker-compose.yaml up --build --exit-code-from tests
```

To run the EDS-only scenario:

``` bash
$ PUBLISH_CLUSTERS=false ENVOY_CONFIG=./envoy-eds.yaml docker compose -f control-plane/docker-compose.yaml up --build --exit-code-from tests
```

To clean up containers and networks:

``` bash
$ docker compose -f control-plane/docker-compose.yaml down --remove-orphans
```

## What This Proves

The tests verify the happy path for both architectures:

- The supervisor can run dedicated CDS and EDS services together.
- The supervisor can serve EDS without serving or publishing CDS.
- Supervised Falcon workers can publish endpoints.
- Envoy can subscribe to those endpoints using EDS.
- Envoy can load balance requests across the supervised workers.

This is a framework for lifecycle testing rather than the complete production story. Follow-up cases should cover worker removal, worker recovery, health changes, and xDS stream reconnects.
