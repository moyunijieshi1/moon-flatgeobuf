const assert=require('node:assert/strict');
const api=require('./api.cjs');
const input={type:'FeatureCollection',features:[{type:'Feature',geometry:{type:'Polygon',coordinates:[[[0,0],[1,0],[1,1],[0,0]]]},properties:{id:1,name:'安全边界'}}]};
const bytes=api.encode(JSON.stringify(input),true);
let rejected=0,checked=0;
function check(data,expectInvalid=false){
  const report=JSON.parse(api.report(data));
  assert.equal(typeof report.valid,'boolean');
  assert.ok(Array.isArray(report.diagnostics));
  if(expectInvalid)assert.equal(report.valid,false);
  if(!report.valid)rejected++;
  checked++;
}
for(let end=0;end<bytes.length;end++)check(bytes.subarray(0,end),true);
for(let i=0;i<bytes.length;i++){
  for(const value of [0,255]){
    const copy=Uint8Array.from(bytes);copy[i]=value;check(copy);
  }
}
let state=0x12345678;
for(let i=0;i<250;i++){
  const length=i%97;
  const random=Uint8Array.from({length},()=>{state=(Math.imul(state,1664525)+1013904223)>>>0;return state&255;});
  check(random,true);
}
console.log(`Malformed-input audit: ${checked} bounded cases, ${rejected} rejected, no uncaught parser failures`);
