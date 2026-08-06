# Releases

## Unreleased

  - Serve endpoints from a dedicated `EndpointDiscoveryService` instead of the aggregated discovery service, leaving ADS available for cluster, listener and route configuration.
  - Stop publishing cluster resources. Declare clusters in Envoy, or in a separate control plane, including their protocol options, active health checks and load-balancing policy.
  - Remove the `health_checks:` monitor option, which only configured published clusters.
  - Stop validating endpoint schemes and protocols, which only constrained the cluster resources the monitor no longer publishes. Out-of-band ORCA still rejects Unix socket endpoints, because it cannot identify a worker without a distinct address.
  - Publish endpoint assignments only when they change, instead of on every reconciliation.
  - Use normalized processor utilization from `process-metrics` v0.13.

## v0.4.0

  - Publish configured active health checks with Envoy clusters.

## v0.3.1

  - Add Bake tasks for inspecting Envoy monitor status, clusters, and endpoints.

## v0.3.0

  - Add supervisor-driven out-of-band ORCA load reporting for independently addressable workers.

## v0.2.0

  - Accept the required Falcon listener as a positional worker preparation argument.

## v0.1.0

  - Deduplicate immutable endpoint values reported by multiple supervised workers and aggregate their health.

## v0.0.1

  - Register concrete Falcon cluster listeners as Envoy upstream endpoint state after binding.
  - Publish grouped IP and Unix-domain-socket endpoint addresses to Envoy.
  - Configure generated clusters from each endpoint's supported HTTP protocol names.
