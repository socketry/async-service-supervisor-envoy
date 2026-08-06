# Control Plane Testing

This scenario exercises the intended Envoy control plane topology:

- Falcon workers register with `Async::Service::Supervisor::Worker`.
- Each worker publishes `state[:endpoint]` with its name, scheme, supported protocols, and concrete addresses.
- `Async::Service::Supervisor::Envoy::Monitor` maps supervisor state into Envoy endpoint assignments.
- Envoy connects to the supervisor's dedicated CDS and EDS services and subscribes to cluster and endpoint updates.
- Envoy routes HTTP traffic to the supervised Falcon workers.

Only the management cluster is declared statically in `envoy.yaml`. The application cluster and its endpoints are discovered from the supervisor.

Envoy initiates the connection. The supervisor does not call Envoy's admin API or mutate Envoy directly. Once Envoy has connected and subscribed, the supervisor streams updates over that connection. This matches the normal xDS control plane model and gives Envoy ownership of reconnects, resource ACK/NACK handling, and sidecar lifecycle.

## Running Tests

``` bash
$ docker compose -f control-plane/docker-compose.yaml up --build --exit-code-from tests
```

To clean up containers and networks:

``` bash
$ docker compose -f control-plane/docker-compose.yaml down --remove-orphans
```

## What This Proves

The test verifies the happy path for the desired architecture:

- The supervisor can run dedicated cluster and endpoint discovery services.
- Supervised Falcon workers can publish endpoints.
- Envoy can subscribe to those endpoints using EDS.
- Envoy can load balance requests across the supervised workers.

This is a framework for lifecycle testing rather than the complete production story. Follow-up cases should cover worker removal, worker recovery, health changes, and xDS stream reconnects.
