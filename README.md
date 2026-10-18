# Moon FlatGeobuf

English · [中文说明](docs/README.zh-CN.md)

Pure MoonBit FlatGeobuf 2D feature reader/writer, packed spatial-index queries,
incremental streams, and a transport-independent HTTP Range query state machine.
Use it to exchange `.fgb` files with existing GIS tools, select a local region,
or load only the matching features from an object-storage archive.

## Install

```sh
moon add moyunijieshi1/moon-flatgeobuf
```

Import the library in `moon.pkg`:

```moonbit
import {
  "moyunijieshi1/moon-flatgeobuf" @fgb,
}
```

The pure codec has no third-party runtime dependencies. It uses MoonBit core.
The Node.js CLI and HTTP adapter are optional hosts; the official JavaScript
FlatGeobuf package is a development-only independent test oracle.

## Library example

```moonbit
let header = @fgb.Header::new(@fgb.Point, [@fgb.Column::new("name", 11)])
let dataset : @fgb.Dataset = {
  header,
  features: [{
    geometry: Some(@fgb.Geometry::point(116.4, 39.9)),
    properties: [@fgb.Text("Beijing")],
  }],
}
let bytes = @fgb.write_dataset(dataset)
let reader = @fgb.Reader::open(bytes)
reader.validate()
let hits = reader.query({
  min_x: 116.0, min_y: 39.0, max_x: 117.0, max_y: 40.0,
})
```

Run the complete example with `moon run examples/basic --target js`.

## CLI

Node.js 24 is required by the acceptance scripts. Build the MoonBit host first:

```sh
moon build --target js
node scripts/cli.cjs encode examples/places.geojson places.fgb
node scripts/cli.cjs inspect places.fgb
node scripts/cli.cjs validate places.fgb
node scripts/cli.cjs query places.fgb 115 38 118 41 selected.geojson
node scripts/cli.cjs decode places.fgb restored.geojson
node scripts/cli.cjs remote https://your-host/data.fgb 115 38 118 41 remote.geojson
```

Outputs are created exclusively: an existing destination causes an error.
The remote command needs HTTP 206, a correct `Content-Range`, a strong ETag,
unchanged object size, and identity content encoding. It sends `If-Match` after
the first response. Redirects and servers ignoring Range are rejected.
The actual socket/filesystem work is in Node.js; binary parsing, traversal,
response validation, and query state transitions are implemented in MoonBit.

## Scope

- Six 2D families: Point, MultiPoint, LineString, MultiLineString, Polygon,
  MultiPolygon; null geometries in unindexed files.
- All 15 standard attribute types; Int64/UInt64 remain exact in the MoonBit API.
- Header, column and CRS metadata; fixed dataset-wide schemas.
- Sequential, ordinal and indexed bounding-box access; field projection,
  property predicates, pagination and GeoJSON conversion.
- Packed file index read/write; deterministic Hilbert sorting on write.
- Incremental stream decoding that discards index bytes; unindexed streaming
  writer with an unknown count; bounded range cache and request coalescing.
- Structural audit, uniqueness checks and dataset statistics.

Bounding-box matches are **candidates**, not exact polygon intersections. The
library does not reproject coordinates or render maps. Z/M/T/TM, geometry
collections, curve geometries and per-feature schemas are explicitly unsupported.
Offsets use a bounded Int32 address space. Defaults cap files at 1 GiB and
features at 16 MiB; see `Limits` and [SUPPORTED_FORMAT.md](SUPPORTED_FORMAT.md).

Indexed queries trust the on-disk index for pruning. Call `Reader::validate`
before querying an untrusted local archive when completeness matters. A partial
remote query cannot prove the correctness of unvisited subtrees.

## Verification

```sh
moon fmt --check
moon check --target all --deny-warn
moon build --target all --deny-warn
moon test --target all --deny-warn
moon run examples/basic --target js
npm ci --ignore-scripts
node scripts/interop.cjs
node scripts/http-test.cjs
node scripts/malformed.cjs
python3 scripts/count-lines.py
```

`--target all` includes native and requires a C toolchain; Linux GitHub Actions
provides one. JS and WasmGC checks also run locally on Windows. See
[INTEROPERABILITY.md](INTEROPERABILITY.md) for evidence and limitations.

## Source and license

BSD-2-Clause. This is an independent MoonBit implementation of the published
FlatGeobuf format, with documented reference behavior. No claim is made to be
the official FlatGeobuf project. See [THIRD_PARTY.md](THIRD_PARTY.md).
