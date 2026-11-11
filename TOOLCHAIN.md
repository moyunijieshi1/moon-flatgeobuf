# Toolchain baseline

Windows development verification on 2026-11-11 used:

- moon 0.1.20261104 (940aa18)
- moonc v0.10.20+65efd5b93
- Matching official standard library
- Node.js 24, and GDAL 3.11.5 Python bindings in a separate conda-forge environment
- Official FlatGeobuf JavaScript package 4.4.0, locked in package-lock.json

The new source uses the current `#derive` syntax. Use the tested compiler or a
compatible newer toolchain. CI prints the actual compiler version, enforces
the contest minimum of 0.10.16, and checks JS, Wasm, WasmGC and native on Linux.
Native builds require a C compiler. A successful Windows JS build does not
verify a Windows native build.
