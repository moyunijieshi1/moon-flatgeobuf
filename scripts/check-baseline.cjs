const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const baseline=JSON.parse(fs.readFileSync(path.join(root,'docs/compatibility-baseline.json'),'utf8'));
assert.equal(baseline.format_version,'3.0.1');
assert.equal(baseline.magic_hex,'6667620366676201');
for(const [file,expected] of Object.entries(baseline.snapshot_sha256)){
  const data=fs.readFileSync(path.join(root,'spec/flatgeobuf-3.0.1',file));
  assert.equal(crypto.createHash('sha256').update(data).digest('hex'),expected,`baseline drift in ${file}`);
}
const pkg=JSON.parse(fs.readFileSync(path.join(root,'package.json'),'utf8'));
const lock=JSON.parse(fs.readFileSync(path.join(root,'package-lock.json'),'utf8'));
assert.equal(pkg.devDependencies.flatgeobuf,baseline.oracle_npm_version);
assert.equal(lock.packages['node_modules/flatgeobuf'].version,baseline.oracle_npm_version);
assert.equal(lock.packages['node_modules/flatgeobuf'].integrity,baseline.oracle_integrity);
assert.equal(baseline.final_milestone_delivered,false,'Do not declare full compatibility without completing the matrix');
console.log(`Compatibility baseline verified: format ${baseline.format_version}, schema commit ${baseline.upstream_commit}, oracle ${baseline.oracle_npm_version}`);
