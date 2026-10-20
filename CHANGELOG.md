# Changelog

## 0.2.0

- Fix the compatibility contract to file format 3.0.1 and exact reference schema
  commit, distinct from the pinned JavaScript oracle version 4.4.0.
- Add mixed, nested and empty 2D GeometryCollection through binary/GeoJSON,
  bounds, indexed/remote queries and streaming; enforce total geometry-node,
  coordinate and depth limits.
- Document all pending format capabilities and final complete-compatibility
  gates instead of equating standard geometry support with the entire format.
- Extend the independent reference comparison matrix to 42 checks.

## 0.1.0

- Introduce six supported 2D geometry families and all standard attribute types.
- Read/write aligned FlatBuffers headers and records, preserving schema metadata.
- Build and query packed spatial indexes; deterministic Hilbert ordering.
- Add GeoJSON, schema inference, projection, predicates and bounded pagination.
- Add incremental streams, remote range queries, cache utilities and diagnostics.
- Add official implementation comparisons, local HTTP acceptance and all-backend CI.
