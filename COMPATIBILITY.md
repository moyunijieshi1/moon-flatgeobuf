# FlatGeobuf compatibility matrix

The file-format baseline is **3.0.1** (writer magic `66 67 62 03 66 67 62 01`).
The pinned upstream schema snapshot is commit
[`3df4db1a9551821f66a1d789bb8632c8076926be`](https://github.com/flatgeobuf/flatgeobuf/tree/3df4db1a9551821f66a1d789bb8632c8076926be),
tag `ts-4.4.0`. The JavaScript test library version 4.4.0 is not the file
version. The schema hashes and test oracle versions are recorded in
[the baseline manifest](docs/compatibility-baseline.json).

Version 0.3.0 delivers the native binary model and the following verified
coverage. The earlier 0.2.1 XY-only submission lacked these native paths.
Coverage is stated by field and independent test case, not as a guarantee
about every file from every producer.

| Schema item | 0.3.0 binary behavior and evidence |
| --- | --- |
| Unknown (0) | Header discriminator. Each heterogeneous record supplies its concrete type; the generated-schema suite includes mixed records. |
| Point (1), LineString (2), Polygon (3), MultiPoint (4), MultiLineString (5), MultiPolygon (6), GeometryCollection (7) | Native coordinates, ends and recursive parts retained; GDAL and generated-schema cases. |
| CircularString (8), CompoundCurve (9), CurvePolygon (10), MultiCurve (11), MultiSurface (12) | Native curve control points and member types retained; GDAL read-back of ISO WKB. Curve XY bounds include arc extrema. |
| Curve (13), Surface (14) | Abstract categories, not concrete geometry payloads. Concrete members must identify their type. |
| PolyhedralSurface (15), TIN (16), Triangle (17) | Surface parts or triangle rings retained according to the pinned representation; GDAL read-back. |
| Z, M, T, TM | Native vectors retain dimension flags and values. Generated-schema cases exercise all 16 flag combinations and exact UInt64 TM. GDAL checks Z/M, not T/TM. |
| Dataset and per-feature columns | Absent, supplied and explicitly empty local schemas retained; records can override the global schema. Property keys use ordinal, not column name. All 15 property types are in the generated-schema matrix. |
| Optional metadata, CRS, envelope | Native tables preserve absent versus empty strings and vectors; the generated-schema reader compares field values. |
| Null and typed empty geometry | Null table, empty XY/parts vectors and empty Point with NaN XY are distinct on the native path. GDAL's own files may encode a typed empty as null; those comparisons use the stored result. |
| Indexed and unindexed archives | Native read/write, preserved order, index rebuild and XY query; known counts and unindexed unknown counts. Native streaming and range reads share validated byte framing with the XY path. |
| Corrupt or oversized data | Checked byte bounds, shape and vector cardinality, limits on depth, total geometry nodes/end entries and coordinates. Truncation and malformed native inputs are tested. |

## Independent checks

- `node scripts/native-schema-test.cjs` generates the reference records
  with the official FlatBuffers classes from `flatgeobuf@4.4.0`. MoonBit
  reads and writes them; the independent classes read the output, comparing
  geometry, vectors, order, flags, schemas, metadata and typed attributes.
  The suite also checks streamed records, real local HTTP ranges and
  representative malformed native input.
- `python scripts/gdal-interop.py` creates files through GDAL 3.11.5 and
  rereads the MoonBit output with GDAL. The comparison uses ISO WKB bytes
  and field values, not feature counts alone. The WKT fixture descriptions
  are in the script. The GDAL driver is not used as an oracle for T/TM or
  per-feature schemas it does not expose.
- The original official JS GeoJSON comparisons, malformed-input audit, real
  Natural Earth query test, and backend test suite remain in CI.

## Explicit boundaries

The native binary API and the 2D GeoJSON adapter are separate. Curves and
non-XY dimensions are not coerced to fit the latter. Type and coordinate
values are compared semantically; byte-identical output, matching every
producer's default layout, exact topology and all future revisions are
outside the contract. An indexed output needs nonempty finite XY boxes;
unindexed output preserves empties. R-tree matching is a candidate filter,
and an HTTP partial read cannot validate unvisited branches. The library
uses Int32 addresses with configurable limits, including the 1 GiB default
archive limit.
