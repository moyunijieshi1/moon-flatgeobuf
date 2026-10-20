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
