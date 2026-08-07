# Releases

## v0.5.0

  - Serve clusters and endpoints through dedicated CDS and EDS services instead of the aggregated discovery service, leaving ADS available for listener, route, and other configuration.
  - Allow cluster publication to be disabled when clusters are owned by another control plane.
  - Configure generated clusters to obtain endpoint assignments from the dedicated EDS service.
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
