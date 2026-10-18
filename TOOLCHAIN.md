# Toolchain baseline

Validated baseline on 2026-10-18:

- moon 0.1.20261012 (748b63c, 2026-10-12)
- moonc v0.10.15+943464bfa
- Matching official core-latest downloaded on the same date
- Node.js v24.19.0 for local acceptance scripts
- Official FlatGeobuf JavaScript package 4.4.0, lockfile included

The implementation uses Int32 names, explicit derived trait exports and the
current labelled-argument syntax after the October formatter migration. The
compiler-specific JavaScript Result lowering is isolated in scripts/api.cjs.
It must be retested when upgrading the compiler. Core APIs are cross-backend;
the optional `host` artifact exports CommonJS functions for Node.js.

CI installs the current official stable toolchain and checks all four backends
on Linux. Local Windows checks cover JS and WasmGC; native Linux checks are
performed in CI with its C compiler. A Windows native build needs a compatible
C compiler and is not part of the local acceptance claim.
