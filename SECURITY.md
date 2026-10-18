# Parser boundaries

Decode untrusted data with explicit application limits. File sizes, offsets,
vectors, coordinates, strings, feature count and recursion depth are bounded.
The supported address space is Int32; oversized u64 values are rejected.

`Reader::validate` scans every record and index node to check structural
consistency. Ordinary local/remote queries trust the index to avoid full reads;
an incorrect envelope in an unvisited node can hide matches. For results whose
completeness is security-relevant, validate the archive first or use a trusted
producer. Validation does not establish the authenticity of external data.

Remote host reads require strong ETags and identity encoding. Each later request
uses If-Match. The adapter rejects redirects and bounds response-body buffering.
Apply network access policy in the embedding application before accepting URLs
from untrusted users. This library does not provide an HTTP proxy service.

Geometry validation checks supported representation and finite coordinates; it
does not validate complete polygon topology or implement coordinate projection.

Please report a reproducible parser failure through the repository's GitHub
security reporting mechanism when enabled, or contact the maintainer without
including confidential data in public issues.
