# Verification evidence

Local results on 2026-10-18, using the October toolchain in TOOLCHAIN.md.

## Independent implementation

`node scripts/interop.cjs` uses the official FlatGeobuf JavaScript 4.4.0 package.
It makes 27 independent comparisons covering both write directions, indexed and
unindexed files, Unicode, nullable fields, multiple geometry families and range
query results. Each side's coordinates, properties and feature identities are
compared, not just counts. Missing nullable properties in the official JS reader
are normalized to omitted keys for comparison, as documented in the test.

An actual eight-byte record-alignment problem was found by this independent
reader and fixed. The tests therefore cover a boundary that internal round-trip
tests alone did not detect. Comparisons do not prove compatibility with every
GDAL version or every optional FlatGeobuf type. GDAL/QGIS GUI testing has not
been performed and is not claimed.

## Real HTTP transport

`node scripts/http-test.cjs` starts an independent local Node HTTP server and
executes real fetch requests through the optional adapter. A 1000-point fixture
produces a 235224-byte indexed file. Querying x=100–110 and y=0–6 yields:

| Metric | Observed value |
| --- | --- |
| HTTP requests | 37 |
| Response bytes including repeated prefixes | 9904 |
| Index nodes read | 181 |
| Feature bodies decoded | 11 |
| Matches returned | 11 |

The test checks If-Match on later requests and rejects four server failure
modes: ignored Range, compressed body, changing ETag and short/mismatched range.
These are fixture-specific observations, not universal performance claims.

## Core regression tests

26 MoonBit tests currently pass on JavaScript and WasmGC locally. Some contain
multiple inputs: all 15 property types, six geometry types, 40 spatial query
boxes checked against full scans, seven streaming chunk sizes including one
byte, empty and singleton trees, limits, nullability, precise integer handling,
schema projection, invalid ranges and cache invalidation.

`node scripts/malformed.cjs` audits 3226 cases: every truncation of a constructed
archive, byte mutations and deterministic random short inputs. 1853 were
rejected with structured diagnostics and there were no uncaught parser failures.
Some byte mutations remain valid by design. This is regression evidence, not a
proof of arbitrary-input safety or a substitute for future fuzzing.

All-backend native verification and interface drift checking run in GitHub
Actions. Refer to the exact successful workflow associated with a commit before
asserting a native pass. Test results must be rerun after changes.
