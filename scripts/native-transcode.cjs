// Binary-only format preservation: no conversion through GeoJSON.
const fs = require('node:fs');
const api = require('./api.cjs');
const [input, output] = process.argv.slice(2);
if (!input || !output) throw new Error('Usage: node scripts/native-transcode.cjs input.fgb output.fgb');
fs.writeFileSync(output, api.native_transcode(fs.readFileSync(input)), {flag:'wx'});
