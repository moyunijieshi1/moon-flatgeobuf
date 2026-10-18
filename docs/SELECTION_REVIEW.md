# Selection review

Date: 2026-10-18. This is a dated public-search result, not a guarantee against
private, unindexed or future work and not an organizer's eligibility approval.

The official Mooncakes website source identified its current search endpoint:
`https://mooncakes.io/api/v0/search?kw=KEYWORD&limit=100`.
Queries flatgeobuf, fgb, Flat Geobuf and geobuf each returned an empty array.
GitHub repository queries `flatgeobuf MoonBit` and `flatgeobuf language:MoonBit`
each returned total_count 0; the latter were repeated before implementation.
Web search for MoonBit plus FlatGeobuf/.fgb and GitHub FlatGeobuf plus moon.mod
did not find another implementation.

Related packages discovered include:

- totto2727/geo: general geometric primitives and algorithms.
- LING71671/moon_strtree: spatial indexes.
- liyun6666/moon-shapefile: SHP/SHX/DBF file handling.
- yyyt0807/moonmvt: Mapbox Vector Tile codecs.

This project's contribution is standard FlatGeobuf file interoperability and
file-index-directed range reading, not a replacement for those projects' general
geometry or index APIs. Their existence alone does not prove or disprove the
organizer's functional-overlap criterion. Recheck before applying.

PMTiles was rejected as a candidate: although Mooncakes returned zero results,
GitHub contained https://github.com/Orion-XX/MoonPMTiles . NATS, Avro, STOMP,
WebDAV and other candidates were rejected after finding existing packages.

Public sources:

- https://github.com/moonbitlang/mooncakes.io/blob/main/src/page/home/server_search.mbt
- https://mooncakes.io/api/v0/search?kw=flatgeobuf&limit=100
- https://api.github.com/search/repositories?q=flatgeobuf%20language%3AMoonBit
- https://flatgeobuf.org/
- https://github.com/flatgeobuf/flatgeobuf

The generated test data is illustrative. This project has not claimed measured
adoption, actual production users or a demonstrated demand volume. Its practical
use cases are interoperable geographic data exchange, offline regional subsets
and viewport-based reading from remote archives.
