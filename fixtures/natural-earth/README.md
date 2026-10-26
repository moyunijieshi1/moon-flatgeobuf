# Natural Earth fixture

Made with Natural Earth. This unmodified GeoJSON snapshot is public-domain map
data from the Natural Earth project's repository. `source.json` records the
exact source commit, path, SHA-256 and terms-of-use URL. It is test data, not
MoonBit implementation code, and is excluded from source-line claims.

The 177 records contain Polygon/MultiPolygon geometry, rings, islands,
multilingual names, null properties and numeric attributes. Tests preserve all
geometry coordinates and non-null attribute values. Null attributes map to
missing values under the format's property representation.

Bounds use ordinary Cartesian min/max coordinates. Dateline-spanning objects
can have very wide boxes; results are bounding-box candidates, not exact
polygon intersections or political/geographic assertions.

Run `node scripts/real-data.cjs` after building the JS host and installing the
pinned development oracle. The verification runs offline and writes generated
files into the ignored `artifacts/real-data` directory.
