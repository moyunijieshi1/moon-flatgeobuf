/* Offline, independently checked acceptance using the pinned public-domain dataset. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const http = require('node:http');
const api = require('./api.cjs');
const {queryRemote} = require('./remote.cjs');

const fixture = path.join(__dirname, '../fixtures/natural-earth/countries.geojson');
const manifest = require('../fixtures/natural-earth/source.json');

// This oracle walks original GeoJSON coordinates; it never reads the MoonBit index.
function geometryBounds(geometry) {
  const box = [Infinity, Infinity, -Infinity, -Infinity];
  function visit(value) {
    if (typeof value[0] === 'number') {
      box[0] = Math.min(box[0], value[0]); box[1] = Math.min(box[1], value[1]);
      box[2] = Math.max(box[2], value[0]); box[3] = Math.max(box[3], value[1]);
    } else for (const child of value) visit(child);
  }
  visit(geometry.coordinates);
  return box;
}
function intersects(box, query) {
  return box[0] <= query.max_x && box[2] >= query.min_x &&
    box[1] <= query.max_y && box[3] >= query.min_y;
}
function ordered(value) {
  if (Array.isArray(value)) return value.map(ordered);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort()
    .filter(key => value[key] !== null).map(key => [key, ordered(value[key])]));
  return value;
}
function canonical(features) {
  return features.map(f => JSON.stringify(ordered({geometry:f.geometry, properties:f.properties}))).sort();
}
function equalFeatures(actual, expected, context) {
  assert.deepEqual(canonical(actual), canonical(expected), context);
}

async function main() {
  const raw = fs.readFileSync(fixture);
  assert.equal(crypto.createHash('sha256').update(raw).digest('hex'), manifest.sha256);
  const original = JSON.parse(raw);
  assert.equal(original.features.length, manifest.features);
  const boxes = original.features.map(f => geometryBounds(f.geometry));
  const official = await import('flatgeobuf/lib/mjs/geojson.js');
  const indexed = api.encode(raw.toString('utf8'), true);
  const sequential = api.encode(raw.toString('utf8'), false);
  assert.equal(api.audit(indexed), 'ok');
  assert.equal(api.audit(sequential), 'ok');
  equalFeatures(JSON.parse(api.decode(indexed)).features, original.features, 'indexed round trip');
  equalFeatures(JSON.parse(api.decode(sequential)).features, original.features, 'sequential round trip');
  equalFeatures(await Array.fromAsync(official.deserialize(indexed)), original.features, 'official reads MoonBit');
  const reference = official.serialize(original);
  equalFeatures(JSON.parse(api.decode(reference)).features, original.features, 'MoonBit reads official');

  const queries = [
    {name:'central-europe', min_x:10, min_y:45, max_x:15, max_y:50},
    {name:'empty-ocean', min_x:-140, min_y:0, max_x:-139, max_y:1},
    {name:'whole-world', min_x:-180, min_y:-90, max_x:180, max_y:90},
    {name:'boundary-point', min_x:boxes[0][0], min_y:boxes[0][1], max_x:boxes[0][0], max_y:boxes[0][1]},
  ];
  // Reproducible geographic windows exercise several packed-index levels.
  let seed = 20261026;
  const random = () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed / 4294967296; };
  for (let i = 0; i < 32; i++) {
    const x = -180 + random() * 340, y = -80 + random() * 150;
    queries.push({name:`window-${i}`, min_x:x, min_y:y, max_x:x+10, max_y:y+8});
  }
  const rows = [];
  for (const query of queries) {
    const expected = original.features.filter((_, i) => intersects(boxes[i], query));
    equalFeatures(JSON.parse(api.query(indexed, JSON.stringify(query))).features, expected, query.name);
    equalFeatures(JSON.parse(api.query(sequential, JSON.stringify(query))).features, expected, `${query.name}: sequential`);
    const independent = await Array.fromAsync(official.deserialize(indexed, {
      minX:query.min_x, minY:query.min_y, maxX:query.max_x, maxY:query.max_y,
    }));
    equalFeatures(independent, expected, `${query.name}: official index traversal`);
    rows.push({name:query.name, matches:expected.length});
  }

  let serverBytes = 0, serverRequests = 0;
  const etag = '"natural-earth-pinned"';
  const server = http.createServer((req, res) => {
    const match = /^bytes=(\d+)-(\d+)$/.exec(req.headers.range || '');
    if (!match) { res.writeHead(400).end(); return; }
    const start = Number(match[1]), end = Number(match[2]);
    if (start > end || end >= indexed.length) { res.writeHead(416).end(); return; }
    if (req.headers['if-match'] && req.headers['if-match'] !== etag) { res.writeHead(412).end(); return; }
    if (serverRequests > 0) assert.equal(req.headers['if-match'], etag);
    serverRequests++; serverBytes += end - start + 1;
    res.writeHead(206, {'Content-Range':`bytes ${start}-${end}/${indexed.length}`, ETag:etag,
      'Content-Length':end-start+1, 'Content-Type':'application/flatgeobuf'});
    res.end(indexed.subarray(start, end+1));
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let remote;
  try {
    remote = await queryRemote(`http://127.0.0.1:${server.address().port}/countries.fgb`, queries[0]);
    equalFeatures(JSON.parse(remote.geojson).features,
      original.features.filter((_, i) => intersects(boxes[i], queries[0])), 'real HTTP query');
    assert.equal(remote.stats.received_bytes, serverBytes);
    assert.equal(remote.stats.requests, serverRequests);
    assert.ok(serverBytes < indexed.length, 'regional query must avoid full download');
  } finally { await new Promise(resolve => server.close(resolve)); }

  const out = path.resolve(process.argv[2] || path.join(__dirname, '../artifacts/real-data'));
  fs.mkdirSync(out, {recursive:true});
  fs.writeFileSync(path.join(out, 'countries.fgb'), indexed);
  fs.writeFileSync(path.join(out, 'central-europe.geojson'), remote.geojson+'\n');
  const result = {dataset:manifest.name, source_sha256:manifest.sha256, features:original.features.length,
    input_geojson_bytes:raw.length, indexed_fgb_bytes:indexed.length, sequential_fgb_bytes:sequential.length,
    windows_checked:queries.length, independent_query_comparisons:queries.length*3,
    remote:remote.stats, remote_saved_percent:Number((100*(1-serverBytes/indexed.length)).toFixed(2)), windows:rows};
  fs.writeFileSync(path.join(out, 'report.json'), JSON.stringify(result, null, 2)+'\n');
  console.log(JSON.stringify(result, null, 2));
}
main().catch(error => { console.error(error); process.exitCode = 1; });
