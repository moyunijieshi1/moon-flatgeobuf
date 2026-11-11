"""Pinned GDAL 3.11.5 -> MoonBit -> GDAL semantic comparison.

Requires GDAL's Python bindings and a previously built JS host. Test fixtures
are original WKT descriptions in this file; generated files are under artifacts.
"""
import json
import os
from pathlib import Path
import subprocess
from osgeo import gdal, ogr, osr

gdal.UseExceptions()
ogr.UseExceptions()
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'artifacts' / 'gdal-interop'
OUT.mkdir(parents=True, exist_ok=True)
NODE = os.environ.get('NODE_EXE', 'node')
assert gdal.VersionInfo('RELEASE_NAME') == '3.11.5', gdal.VersionInfo('--version')

CASES = {
    'point': 'POINT (1 2)',
    'line': 'LINESTRING (0 0,1 2,3 4)',
    'polygon': 'POLYGON ((0 0,5 0,5 5,0 0),(1 1,2 1,2 2,1 1))',
    'multipoint': 'MULTIPOINT ((1 2),(3 4))',
    'multiline': 'MULTILINESTRING ((0 0,1 2),(3 4,5 6))',
    'multipolygon': 'MULTIPOLYGON (((0 0,1 0,1 1,0 0)),((2 2,3 2,3 3,2 2)))',
    'collection': 'GEOMETRYCOLLECTION (POINT (1 2),LINESTRING (0 0,3 4))',
    'circularstring': 'CIRCULARSTRING (0 0,1 2,2 0)',
    'compoundcurve': 'COMPOUNDCURVE ((0 0,1 0),CIRCULARSTRING (1 0,2 1,3 0))',
    'curvepolygon': 'CURVEPOLYGON (CIRCULARSTRING (0 0,2 2,4 0,2 -2,0 0))',
    'multicurve': 'MULTICURVE (LINESTRING (0 0,1 1),CIRCULARSTRING (2 0,3 1,4 0))',
    'multisurface': 'MULTISURFACE (POLYGON ((0 0,1 0,1 1,0 0)),CURVEPOLYGON (CIRCULARSTRING (2 0,3 1,4 0,3 -1,2 0)))',
    'polyhedral': 'POLYHEDRALSURFACE Z (((0 0 0,1 0 0,1 1 0,0 0 0)))',
    'tin': 'TIN Z (((0 0 1,1 0 2,0 1 3,0 0 1)),((1 0 2,1 1 4,0 1 3,1 0 2)))',
    'triangle': 'TRIANGLE Z ((0 0 1,1 0 2,0 1 3,0 0 1))',
    'point_z': 'POINT Z (1 2 3)',
    'point_m': 'POINT M (1 2 99)',
    'point_zm': 'POINT ZM (1 2 3 99)',
    'line_zm': 'LINESTRING ZM (0 0 1 11,1 2 3 22,3 4 5 33)',
    'circular_zm': 'CIRCULARSTRING ZM (0 0 1 11,1 2 3 22,2 0 5 33)',
    'compound_zm': 'COMPOUNDCURVE ZM ((0 0 1 11,1 0 2 22),CIRCULARSTRING (1 0 2 22,2 1 3 33,3 0 4 44))',
    'empty_point': 'POINT EMPTY',
    'empty_line': 'LINESTRING EMPTY',
    'empty_polygon': 'POLYGON EMPTY',
    'empty_multipoint': 'MULTIPOINT EMPTY',
    'empty_multiline': 'MULTILINESTRING EMPTY',
    'empty_multipolygon': 'MULTIPOLYGON EMPTY',
    'empty_collection': 'GEOMETRYCOLLECTION EMPTY',
    'empty_curve': 'CIRCULARSTRING EMPTY',
    'empty_compound': 'COMPOUNDCURVE EMPTY',
    'empty_curvepolygon': 'CURVEPOLYGON EMPTY',
    'empty_multicurve': 'MULTICURVE EMPTY',
    'empty_multisurface': 'MULTISURFACE EMPTY',
    'empty_polyhedral': 'POLYHEDRALSURFACE EMPTY',
    'empty_tin': 'TIN EMPTY',
    'empty_triangle': 'TRIANGLE EMPTY',
    'nested_curves': 'GEOMETRYCOLLECTION (COMPOUNDCURVE ((0 0,1 0),CIRCULARSTRING (1 0,2 1,3 0)),GEOMETRYCOLLECTION (POINT (10 20),MULTIPOINT ((2 2),(3 3))))',
}

def snapshot(file):
    ds = ogr.Open(str(file))
    assert ds is not None, str(file)
    layer = ds.GetLayer(0)
    definition = layer.GetLayerDefn()
    fields = [(definition.GetFieldDefn(i).GetName(), definition.GetFieldDefn(i).GetType())
              for i in range(definition.GetFieldCount())]
    features = []
    for feature in layer:
        geometry = feature.GetGeometryRef()
        features.append({'wkb': bytes(geometry.ExportToIsoWkb()).hex() if geometry else None,
                         'fields': [feature.GetField(i) for i in range(feature.GetFieldCount())]})
    return {'fields': fields, 'features': features}

results = []
for name, wkt in CASES.items():
    geometry = ogr.CreateGeometryFromWkt(wkt)
    assert geometry is not None, (name, wkt)
    for indexed in ([False] if geometry.IsEmpty() else [False, True]):
        stem = f'{name}-{"index" if indexed else "scan"}'
        source = OUT / f'{stem}.fgb'
        target = OUT / f'{stem}-moon.fgb'
        for file in [source, target]:
            if file.exists(): file.unlink()
        ds = ogr.GetDriverByName('FlatGeobuf').CreateDataSource(str(source))
        srs = osr.SpatialReference()
        srs.ImportFromEPSG(4326)
        layer = ds.CreateLayer('case', srs, geometry.GetGeometryType(),
                              options=[f'SPATIAL_INDEX={"YES" if indexed else "NO"}'])
        for field, kind in [('name', ogr.OFTString), ('exact', ogr.OFTInteger64), ('value', ogr.OFTReal)]:
            layer.CreateField(ogr.FieldDefn(field, kind))
        feature = ogr.Feature(layer.GetLayerDefn())
        feature.SetField('name', '曲线与维度')
        feature.SetField('exact', 9007199254740993)
        feature.SetField('value', 1.25)
        feature.SetGeometry(geometry)
        layer.CreateFeature(feature)
        feature = None
        layer = None
        ds = None
        expected = snapshot(source)
        subprocess.run([NODE, str(ROOT / 'scripts/native-transcode.cjs'), str(source), str(target)],
                       cwd=ROOT, check=True, capture_output=True, text=True)
        assert snapshot(target) == expected, stem
        results.append({'case': stem, 'passed': True, 'source_bytes': source.stat().st_size,
                        'rewritten_bytes': target.stat().st_size})

report = {'oracle':gdal.VersionInfo('--version'), 'cases':len(results), 'results':results}
(OUT / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
print(f'GDAL native format interoperability: {len(results)} cases passed')
