# Versioned compatibility contract

## Fixed baseline

The file format target is **FlatGeobuf 3.0.1**. This is the format changelog's
version introducing the required eight-byte alignment, not the JavaScript
library's semantic version. Writer magic is `66 67 62 03 66 67 62 01`.
Readers retain the documented forward-compatible patch-byte acceptance policy;
unknown major versions are rejected rather than inferred to be compatible.

The exact schema snapshot is the upstream repository at tag `ts-4.4.0`, commit
`3df4db1a9551821f66a1d789bb8632c8076926be`. Files under spec/flatgeobuf-3.0.1
are byte-for-byte copies with the upstream license. The manifest in
docs/compatibility-baseline.json pins their SHA-256 hashes, and pins the separate
independent oracle to npm `flatgeobuf@4.4.0` and its SHA-512 integrity. CI checks
these pins. Upgrading the baseline requires a deliberate manifest change and
new test evidence; following upstream HEAD is not an implicit upgrade.

Sources:

- https://github.com/flatgeobuf/flatgeobuf/blob/3df4db1a9551821f66a1d789bb8632c8076926be/doc/format-changelog.md
- https://github.com/flatgeobuf/flatgeobuf/blob/3df4db1a9551821f66a1d789bb8632c8076926be/src/fbs/header.fbs
- https://github.com/flatgeobuf/flatgeobuf/blob/3df4db1a9551821f66a1d789bb8632c8076926be/src/fbs/feature.fbs

## Current 0.2.1 delivery

**0.2.1 is a bounded XY linear-geometry profile, not full format compatibility.**
It includes legal 2D GeometryCollection records, including mixed children, arbitrary
supported nesting up to max_depth, and empty collections. The binary codec,
GeoJSON import/export, inferred/mixed headers, bounds, ordinal access, streaming
and remote queries all use the same recursive geometry representation. This
does not flatten collections into MultiPolygon or discard child types.

Both homogeneous GeometryCollection headers and Unknown mixed-type headers are
tested in both directions against the pinned oracle. The nested members include
points, lines, MultiPolygon and empty collections. Depth, total coordinate and
total geometry-node budgets apply across one entire feature, including empty
children. An invalid child lacking its concrete type is rejected. Collection
bounds are the union of child bounds. They are candidate boxes, not a test of
exact spatial intersection. Empty collections have no bounds and are preserved
without an index; indexed writing currently rejects them explicitly.

## Final complete-compatibility goal

The **1.0.0 acceptance target** is read/write interoperability for every legal
configuration defined by the fixed schema, within explicit resource limits.
It is not satisfied by seven GeoJSON geometry types. It includes all concrete
GeometryType values, dimensional vectors, valid empty/null representations and
per-feature schemas. Resource-limit failures must be distinguishable from an
unsupported format. Coordinates, scalar values, optional field semantics,
metadata, child order and type identity must survive a read/write cycle; exact
original byte layout and full computational topology are not goals.

The target is **not delivered** in 0.2.1. Pending rows below remain obligations
for that milestone, not hidden exclusions or current feature claims.

| Schema item | 0.2.1 status | 1.0.0 target |
| --- | --- | --- |
| Unknown (0) | Mixed header discriminator; not a concrete child | Same discriminator semantics |
| Point (1) | Nonempty XY read/write | All legal dimensional/empty forms |
| LineString (2) | Nonempty XY read/write | All legal dimensional/empty forms |
| Polygon (3) | Nonempty XY read/write | All legal dimensional/empty forms |
| MultiPoint (4) | Nonempty XY read/write | All legal dimensional/empty forms |
| MultiLineString (5) | Nonempty XY read/write | All legal dimensional/empty forms |
| MultiPolygon (6) | XY Polygon parts | All legal dimensional/empty forms |
| GeometryCollection (7) | XY mixed/nested/empty read/write | All legal dimensional combinations |
| CircularString (8) | Explicit unsupported error | Lossless native-format read/write |
| CompoundCurve (9) | Explicit unsupported error | Lossless native-format read/write |
| CurvePolygon (10) | Explicit unsupported error | Lossless native-format read/write |
| MultiCurve (11) | Explicit unsupported error | Lossless native-format read/write |
| MultiSurface (12) | Explicit unsupported error | Lossless native-format read/write |
| Curve (13) | Explicit unsupported error | Handle wherever baseline permits; reject invalid abstract instances |
| Surface (14) | Explicit unsupported error | Handle wherever baseline permits; reject invalid abstract instances |
| PolyhedralSurface (15) | Explicit unsupported error | Lossless native-format read/write |
| TIN (16) | Explicit unsupported error | Lossless native-format read/write |
| Triangle (17) | Explicit unsupported error | Lossless native-format read/write |
| Z/M/T/TM vectors and corresponding envelopes | Explicit unsupported error | Consistent dimensions and vector cardinality |
| All 15 properties, global schema and CRS metadata | Implemented bounded profile | Independent boundary/type matrix |
| Per-feature column schemas | Explicit unsupported error | Preserve and expose effective schema per feature |
| Null geometry and empty GeometryCollection | Unindexed read/write | Every valid baseline representation/index rule |
| Other empty geometry forms | Explicit rejection | Distinguish valid empties from invalid buffers |
| Header count 0, mixed type, indexed/unindexed, streams | Implemented profile | Full cross-product regression matrix |

Curves must not be silently linearized, and 3D/time vectors must not be dropped
to fit GeoJSON. Formats not representable in RFC 7946 need native API preservation
and an explicit GeoJSON conversion error. This milestone does not promise
rendering, reprojection, self-intersection repair or an unbounded file size.

## Completion gates

1. Each legal row needs independently produced reference fixtures and an
   implementation-to-reference read-back comparison. The JavaScript GeoJSON
   oracle covers the seven standard types but does not establish curve or all
   dimensional support. Before closing those rows, pin a capable upstream
   GDAL/C++ implementation and record its exact version, fixture provenance and
   licenses. No unexecuted GDAL test is counted as passed.
2. Compare actual types, nested child order, coordinates/dimensions, ring ends,
   attributes, exact 64-bit values, null/empty meaning and schema metadata;
   feature counts alone are insufficient. Compare semantics rather than
   requiring identical FlatBuffers byte layout or generated record order.
3. For each indexed configuration, compare local and remote query candidates
   with a full scan. Include empty results, boundary contacts and nesting. Audit
   index completeness separately from partial remote-query validation.
4. Exercise malformed vectors, wrong type/shape combinations, truncations,
   overflow, nesting and aggregate node/coordinate budgets on all backends.
5. Publish the completed matrix and reproducible commands, with no legal row
   marked pending, before describing the release as fully compatible with the
   fixed baseline. Current 0.2.1 evidence is limited to its documented profile.
