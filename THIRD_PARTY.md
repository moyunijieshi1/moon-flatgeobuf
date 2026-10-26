# Sources and licenses

Moon FlatGeobuf is independently authored in MoonBit with AI assistance. It is
not a translated checkout or an official FlatGeobuf implementation. Behavioral
and binary-layout references were inspected; no reference implementation source
file is included in the runtime library.

| Source | Purpose | License |
| --- | --- | --- |
| https://github.com/flatgeobuf/flatgeobuf | Schema definitions, format layout, packed-tree behavior, independent JavaScript oracle | BSD-2-Clause |
| https://flatgeobuf.org/ | Format documentation and ecosystem compatibility | See upstream repository license |
| https://github.com/moonbitlang/core | Standard library, toolchain-provided runtime | Apache-2.0 |
| https://github.com/nvkelso/natural-earth-vector | Pinned real-world GeoJSON test fixture | Public domain; see fixtures/natural-earth/source.json and README.md |

The project uses its own BSD-2-Clause license. The `flatgeobuf` npm dependency
and its transitive dependencies are used only by development acceptance tests.
They retain their own notices and are not bundled in the published MoonBit
codec. `npm ci --ignore-scripts` installs the exact versions in package-lock.json.

The examples/places.geojson fixture is hand-authored illustrative data, not a
downloaded geographic database. Test geometries and records are constructed by
the tests and contain no private information. Official FlatGeobuf serialization
produces independent test files at runtime; no external map dataset is bundled.

The Hilbert ordering uses the standard iterative coordinate rotation algorithm.
FlatBuffers writing is implemented directly with explicit alignment and forward
references; no generated FlatGeobuf schema bindings are shipped. Explicit
derived-trait exports in trait_extensions.generated.mbt are generated from this
project's declarations and are excluded from implementation-line counts.

The schema and changelog files under spec/flatgeobuf-3.0.1 are verbatim reference
definitions from upstream tag ts-4.4.0, commit
3df4db1a9551821f66a1d789bb8632c8076926be. Their original BSD-2-Clause license
is retained alongside them. These are specification snapshots, not runtime
implementation code, and do not enter the MoonBit implementation line count.
The file-format version is 3.0.1 according to that changelog; JavaScript oracle
4.4.0 is a separate pinned implementation release.
