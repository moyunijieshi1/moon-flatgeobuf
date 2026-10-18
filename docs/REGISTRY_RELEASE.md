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
