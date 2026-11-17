# Current acceptance: 0.3.0 (2026-11-17)

This section records executable evidence for the current package. It does not
claim validation of every file produced by every GIS application.

- `moon check`, `moon build`, and 65 tests pass on JS, Wasm, WasmGC, and native
  with moonc 0.10.20. Two proposal-level tests cover multiple indexed features,
  different record-local schemas, one-byte chunks, window selection, output
  archive creation, reopening, and full validation.
- `node scripts/native-schema-test.cjs` makes files with the official generated
  FlatBuffers classes. It performs 1,053 binary comparisons, 271 chunked-stream
  comparisons and four real localhost HTTP Range comparisons, and rejects 297
  representative malformed inputs.
- `python scripts/gdal-interop.py` asks GDAL 3.11.5 to create linear, curved,
  Z/M, surface and legal empty cases. It transcodes each file through the
  MoonBit path and has GDAL compare ISO WKB and field values in 59 cases.
- The current delivered contract is the pinned FlatGeobuf 3.0.1 schema and the
  explicit limits in `COMPATIBILITY.md` and `SUPPORTED_FORMAT.md`: 15 concrete
  geometry codes, Z/M/T/TM vectors, dataset or record-local schemas, null and
  typed-empty geometry in unindexed archives, packed-index queries, streaming,
  and checked HTTP ranges. Abstract Curve (13) and Surface (14) are accepted as
  header categories; feature payloads use a concrete member type.
- The project does not promise exact topology intersection, reprojection,
  byte-identical rewrites, automatic rendering, files beyond configured Int32
  addressing limits, or compatibility with future format revisions.

The three proposal workflows map to concrete checks in the README. The public
package is `moyunijieshi1/moon-flatgeobuf@0.3.0`; GDAL and the JavaScript oracle
are development-only dependencies, not runtime implementations.

---

# Historical acceptance: 0.2.1 (2026-10-26)

Release source: 76b35ec. Verified workflow:
https://github.com/moyunijieshi1/moon-flatgeobuf/actions/runs/40302245022

- All four backends passed 35 tests each; all-backend check/build and example passed.
- 42 existing official interoperability checks and 108 real-data spatial query
  comparisons passed, including all 177 original geometries and attributes.
- Live cancellation, deadlines, rejected-body cleanup, HTTP range and 3226
  malformed-input cases passed. Pinned fixture and schema hash checks passed.
- CI retained the real-data archive, regional GeoJSON and JSON report as artifacts.
- Public registry publishing and independent 0.2.1 consumer installation passed.
- 4191 production MoonBit lines; generated code, tests and data are excluded.

See FINAL_REVIEW.zh-CN.md, real-data-results.json and REGISTRY_RELEASE.md.
Full format 1.0 compatibility is still pending, as listed in COMPATIBILITY.md.
The snapshots below are historical evidence only.

---

# Current acceptance: 0.2.0 (2026-10-20)

Release source: 1776ff9. All four backends passed 32 tests each; 42 independent
comparisons, HTTP range verification, malformed-input audit and baseline hash
checks passed. CI: https://github.com/moyunijieshi1/moon-flatgeobuf/actions/runs/39440876831

0.2.0 was published and independently installed from Mooncakes; see
[REGISTRY_RELEASE.md](REGISTRY_RELEASE.md). This is the bounded XY profile, not
full format compatibility. [The versioned contract](../COMPATIBILITY.md)
records the fixed baseline, remaining gaps and final acceptance conditions.

The older snapshot below is retained as historical evidence only.

---

# Acceptance snapshot

Date: 2026-10-18.

Current publication status: 0.1.0 is now published and independently installed;
see [REGISTRY_RELEASE.md](REGISTRY_RELEASE.md). The snapshot below predates login.

Verified commit: 54e4388.

Successful GitHub workflow:
https://github.com/moyunijieshi1/moon-flatgeobuf/actions/runs/39126580506

- All-backend check, build and tests passed with warnings denied.
- 26 MoonBit tests passed on each configured backend: JS, Wasm, WasmGC, native.
- Complete runnable example passed.
- 27 independent official FlatGeobuf comparisons passed.
- Live HTTP range verification and four adverse-server cases passed.
- 3226 malformed-input audit cases completed without uncaught parser failures.
- 4106 authored implementation lines by scripts/count-lines.py; tests, examples,
  comments, blank lines and generated trait/interface files are excluded.
- Generated public interface matched the committed interface.

At this code snapshot the repository has 17 commits, with behavior-led development
history and one explicit formatting/API migration commit. Commit count is not
presented as a substitute for functionality or quality. All authors use the
repository owner's GitHub noreply identity.

The local `moon package --frozen` command succeeded. Mooncakes publication is
pending the owner's account registration/login; no published-package claim is
made in this snapshot. The prepared module is moyunijieshi1/moon-flatgeobuf
0.1.0. The user must complete authentication personally.

Organizer registration and final eligibility are separate from these engineering
checks. The competition asks for a personally written proposal. A factual
checklist was prepared locally for the contestant and is not represented as a
personally authored application.
