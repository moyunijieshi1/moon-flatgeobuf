# Contributing

Run the verification commands in README.md using the toolchain in TOOLCHAIN.md.
Changes to binary layout must include an independent official-library test.
Changes to query pruning must compare with full scanning, including boundary
contacts and empty/singleton trees. Changes to byte ranges must exercise an
actual HTTP endpoint, not only a mocked return value.

Add supported types deliberately and update SUPPORTED_FORMAT.md. Do not silently
ignore unknown schema fields that would change geometry dimensions or property
interpretation. Keep limits and checked arithmetic on every length/offset path.

Run `python3 scripts/trait-extensions.py` after adding derived public models,
then `moon fmt` and `moon info`. Generated trait exports are not counted as
authored implementation lines. Avoid mechanically expanded code or meaningless
commits. Describe a concrete behavior change in each commit.

Report issues with toolchain version, backend, supported format expectations and
a minimal fixture that can be shared legally. Do not upload private map data or
authentication credentials.
