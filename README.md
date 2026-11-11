# Moon FlatGeobuf

English · [中文说明](docs/README.zh-CN.md)

MoonBit reader and writer for the fixed **FlatGeobuf 3.0.1** binary schema.
Version 1.0.0 adds a native API for all 15 concrete geometry types in the
pinned schema, Z/M/T/TM vectors, local column schemas, and null and typed-empty
geometries. It preserves curved and measured data without a GeoJSON round trip.
See the [compatibility matrix](COMPATIBILITY.md) for test coverage and limits.

## Install and run

Use a current MoonBit toolchain (tested with moonc 0.10.20). Install the
published module in your own project:

```sh
moon add moyunijieshi1/moon-flatgeobuf@1.0.0
```

In `moon.pkg`:

```moonbit
import {
  "moyunijieshi1/moon-flatgeobuf" @fgb,
}
```

The library uses MoonBit core. GDAL and the upstream JS library are test
oracles only; they are not runtime dependencies. In a clone, run:

```sh
moon run examples/native --target js
moon run examples/basic --target js
```

The native example writes an indexed CircularString with Z/M/T/TM and a
local schema, reads it back, and checks a query intersecting the arc's bounds
outside the control points' X range. Expected:
`CircularString with Z/M/T/TM and local schema: one preserved feature`.

## APIs and command line

| Task | API |
| --- | --- |
| Preserve native format fields when reading/writing | `read_native_dataset`, `write_native_dataset` |
| Validate, read by ordinal or query XY bounding boxes | `NativeReader` |
| Decode chunks or emit unindexed records incrementally | `NativeStreamDecoder`, `NativeStreamWriter` |
| Query a remote archive, preserving native feature values | `NativeRangeQuery` |
| Import/export 2D GeoJSON, select fields and filter properties | `Reader`, `write_dataset`, `import_geojson`, `Dataset::to_geojson` |

For a record with a local schema, `NativeFeature::effective_columns` uses it
instead of the header schema. Absent and explicitly empty local schemas remain
distinct. Native writes retain record order and the supplied header; the 2D
writer retains its optional Hilbert ordering.

For the optional Node.js CLI, build with `moon build --target js`. Use Node.js
24. Example commands:

```sh
node scripts/cli.cjs encode examples/places.geojson places.fgb
node scripts/cli.cjs validate-native places.fgb
node scripts/cli.cjs transcode places.fgb rewritten.fgb
node scripts/cli.cjs query-native places.fgb 115 38 118 41 selected.fgb
node scripts/cli.cjs decode places.fgb restored.geojson
```

Use `remote-native URL minX minY maxX maxY output.fgb` for HTTP Range reads.
The host performs HTTP I/O; MoonBit plans byte ranges, checks the response,
and decodes the records. The server must honor Range, provide a stable strong
ETag, and serve uncompressed bytes. CLI output files must not already exist.

The GeoJSON adapter is a separate 2D, dataset-schema path; it rejects inputs
it cannot represent. The binary API is the path for curves, dimensional
vectors, and local schema. Spatial filtering returns XY envelope candidates,
not exact intersections or reprojection. Null or empty geometry has no
finite index box; write such datasets without an index. The default archive
and feature limits are 1 GiB and 16 MiB; offsets are checked Int32 addresses.
See [SUPPORTED_FORMAT.md](SUPPORTED_FORMAT.md).

## Verification

```sh
moon version --all
moon fmt --check
moon check --target all --deny-warn
moon build --target all --deny-warn
moon test --target all --deny-warn
npm ci --ignore-scripts
node scripts/check-baseline.cjs
node scripts/native-schema-test.cjs
node scripts/interop.cjs
node scripts/http-test.cjs
node scripts/remote-cancel-test.cjs
node scripts/malformed.cjs
npm run demo:real-data
```

To reproduce the independent curved geometry checks, install GDAL 3.11.5
Python bindings (e.g. in a conda-forge environment with Python 3.12), then run
`python scripts/gdal-interop.py`. CI runs both independent suites and saves
their reports. A C toolchain is needed for the native MoonBit backend;
see [TOOLCHAIN.md](TOOLCHAIN.md).

The Natural Earth demo checks 177 real features and 36 windows against
independent paths. Transfer counts in its report apply to its specific
window and file, not to arbitrary datasets.

## License

BSD-2-Clause. Independent implementation based on the published format;
not an official FlatGeobuf implementation. [Sources and licenses](THIRD_PARTY.md).
