# Supported format

## Files and addressing

FlatGeobuf major version 3 magic is required; compatible patch bytes are accepted.
The header and features use size-prefixed FlatBuffers. Fields are read through
verified vtables; table objects, vectors, strings, and forward references must
fit their containing buffer. Shared vtables with negative signed displacements
are accepted. Writers use a simple aligned forward layout, not a FlatBuffers
code generator. Records are padded to preserve eight-byte vector alignment.

Header feature count 0 means unknown for unindexed input. Empty output uses a
zero count and no index. Indexed files require a known positive count and node
size 2–65535. The default writer uses node size 16. A singleton has both a root
and leaf as prescribed by the packed tree layout.

Input u64 offsets/counts are checked before conversion to Int32. Addressable
offsets cannot exceed 2 GiB−1; default maximum file size is 1 GiB. This release
does not handle global archives larger than that ceiling. It never silently
wraps large file offsets. `Limits` exposes lower application-specific budgets.

## Geometry

Supported: nonempty 2D Point, MultiPoint, LineString, MultiLineString, Polygon,
MultiPolygon. Polygon rings must be closed and have at least four coordinates;
this checks representation, not self-intersection, winding or full topology.
MultiPolygon uses Polygon parts. Mixed supported types use Unknown in the
header and concrete types per feature. Null geometries are accepted without an
index; indexed output rejects them. Empty non-null geometries are rejected.

Coordinates must be finite. Z/M/T/TM, collections, curves and all other type
codes are rejected. CRS fields are preserved; no projection conversion occurs.
GeoJSON export rejects a declared non-EPSG:4326 CRS unless `allow_projected` is
explicitly set. A missing CRS is treated as caller-owned coordinate semantics;
`Header::validate_geojson_crs` offers a stricter opt-in check. GeoJSON import
defaults to EPSG:4326. `Geometry::validate_wgs84` checks coordinate ranges.

## Properties

| Code | Type | MoonBit value |
| --- | --- | --- |
| 0 | Byte | Integer, checked signed 8-bit |
| 1 | UByte | Unsigned, checked 8-bit |
| 2 | Bool | Boolean, wire value 0 or 1 |
| 3 | Short | Integer, checked signed 16-bit |
| 4 | UShort | Unsigned, checked 16-bit |
| 5 | Int | Integer, checked signed 32-bit |
| 6 | UInt | Unsigned, checked 32-bit |
| 7 | Long | Integer, exact signed 64-bit |
| 8 | ULong | Unsigned, exact unsigned 64-bit |
| 9 | Float | Real, IEEE binary32 rounded on write |
| 10 | Double | Real, finite IEEE binary64 |
| 11 | String | Text, strict UTF-8 |
| 12 | Json | Text holding valid JSON |
| 13 | DateTime | Text; date syntax is retained, not interpreted |
| 14 | Binary | Binary bytes |

Absent keys are null. Missing required fields, duplicate keys, unknown column
indexes, mismatched types and numeric overflow fail explicitly. Schema columns
are dataset-wide. Per-feature schema tables are unsupported. Header metadata
including width/precision/scale is preserved; those descriptive SQL constraints
are not enforced as formatting or rounding instructions. Dataset validation
checks declared uniqueness/primary keys; basic decoding does not enforce global
uniqueness. Custom metadata strings are opaque.

GeoJSON exports exact integer JSON text. Parsing that text with ordinary
JavaScript `JSON.parse` can lose precision beyond 2^53−1; use the MoonBit model
or a lossless JSON parser when those integers matter. The remote host returns
the GeoJSON as text and never reparses it before writing CLI output. Binary
attributes export as arrays of byte numbers. JSON attributes export as JSON
values. DateTime remains text. GeoJSON Feature `id`, `bbox` and foreign members
are not retained unless represented as schema properties.

Inference sorts column names for deterministic schemas. It supports missing or
null values and safe integer/decimal widening. Inconsistent types and mixed
decimals/large exact integers require an explicit schema. Explicit Double
columns deliberately follow binary64 precision. No promise of exact decimal
arithmetic is made.

## Index, streams and remote queries

Packed R-tree nodes occupy 40 bytes: four doubles and one u64 offset. Internal
offsets are child node numbers; leaf offsets are relative to the feature section.
The writer sorts by 16-bit-per-axis Hilbert center keys unless disabled, with
stable input-order tie breaking. Query ordering is archive traversal order.

Bounds queries return candidates based on intersecting bounding boxes. They do
not compute exact polygon intersection. Local `Reader::validate` verifies all
nodes, parent containment, feature boundaries and leaf containment. A partial
query validates visited references but trusts the index for pruning. Remote
validation cannot prove that an unvisited subtree does not hide a match.

StreamDecoder buffers at most one header or one feature plus its size prefix
and discards index bytes. Returned arrays contain this chunk's decoded records;
callers should consume them incrementally. `finish` is mandatory to detect
truncated input and declared-count mismatches. StreamWriter emits an unindexed,
unknown-count archive; each append returns bytes for a caller-owned sink. It
cannot retroactively add an index or rewrite the initial header.

RangeQuery is a MoonBit state machine; the host supplies sockets and scheduling.
It requests the root and intersecting index blocks, then each selected feature's
size and body. Unindexed input falls back to sequential remote scanning. It
requires identity encoding, exact HTTP 206 intervals, unchanged object size and
a strong ETag; the Node host sends If-Match. Missing/weak ETags and redirects
are rejected by this host. This deliberately restricts compatible endpoints.
Requests are currently serial; `coalesce_ranges` is a caller-owned optimization,
not automatically enabled. TransferStats reports actual bytes including repeated
size prefixes. An optional RangeCache belongs to one object URL; clear it before
switching resources, even when validators happen to match.
