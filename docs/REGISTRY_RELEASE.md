# Mooncakes release 0.2.0

Published successfully on 2026-10-20. The official publisher verified the
extracted archive and returned `Server status: 200 OK`.

- Package: https://mooncakes.io/docs/moyunijieshi1/moon-flatgeobuf
- Release source commit: 1776ff9
- Successful CI: https://github.com/moyunijieshi1/moon-flatgeobuf/actions/runs/39440876831
- All four backends passed 32 tests each; 42 official interoperability comparisons passed.
- Real HTTP range and 3226 malformed-input cases passed. Implementation count: 4191 lines.

A new consumer directory installed `moyunijieshi1/moon-flatgeobuf@0.2.0`
from the public registry, with no local path dependency. It constructed nested
GeometryCollections with an empty child, wrote and validated an indexed file,
queried the bounds, compared the complete geometry and round-tripped GeoJSON.

```text
Published 0.2.0 passed: nested/empty collection, binary validation, indexed query and GeoJSON round trip.
```

This release implements the documented XY profile. The full fixed-baseline
1.0 goal is still pending; see [COMPATIBILITY.md](../COMPATIBILITY.md).

---

# Mooncakes release 0.1.0

Published successfully on 2026-10-18 as:

https://mooncakes.io/docs/moyunijieshi1/moon-flatgeobuf

The official publish command validated the extracted package and returned
`Server status: 200 OK`. The public documentation page shows author moyunijieshi1,
version 0.1.0, BSD-2-Clause and the matching GitHub repository.

The published runtime source corresponds to commit 3c6e17a. Earlier pending-login
notes in ACCEPTANCE.md describe that older snapshot; this document supersedes
them for publication status.

A separate consumer directory installed the package from the public registry:

```sh
moon add moyunijieshi1/moon-flatgeobuf@0.1.0
moon run . --target js
```

The smoke test built a Point dataset, wrote an indexed archive, opened and
validated it, queried its bounds and checked the exact name property. Result:

```text
Published package smoke test passed: one feature read, validated, and queried.
```

GitHub account, repository namespace, package namespace and commit author are
all moyunijieshi1. No authentication credentials are included in the project.
