/* Tests use the independently maintained official FlatGeobuf implementation. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const api = require('./api.cjs');

async function main() {
  const official = await import('flatgeobuf/lib/mjs/geojson.js');
  const point = n => ({type:'Point',coordinates:[n, n % 7]});
  const polygon = {type:'Polygon',coordinates:[[[0,0],[5,0],[5,5],[0,0]]]};
  const inputs = [
    Array.from({length:103},(_,i)=>({type:'Feature',geometry:point(i),properties:{id:i,name:`站点-${i}`,active:i%2===0,value:i/10}})),
    [{type:'Feature',geometry:polygon,properties:{name:'区域'}}, {type:'Feature',geometry:{type:'MultiPolygon',coordinates:[polygon.coordinates]},properties:{name:'多区域'}}],
    [{type:'Feature',geometry:{type:'MultiLineString',coordinates:[[[0,0],[1,1]],[[4,4],[5,5]]]},properties:{name:'道路'}}],
    [{type:'Feature',geometry:{type:'MultiPoint',coordinates:[[1,2],[3,4]]},properties:{name:null}}],
  ];
  let checks = 0;
  for (const features of inputs) {
    const collection = {type:'FeatureCollection',features};
    for (const indexed of [false,true]) {
      const own = api.encode(JSON.stringify(collection), indexed);
      assert.equal(api.audit(own),'ok');
      const decoded = await Array.fromAsync(official.deserialize(own));
      assert.equal(decoded.length,features.length);
      // FlatGeobuf omits null properties; official JS exposes them as missing keys.
      const canonical = values => values.map(x=>JSON.stringify({geometry:x.geometry,properties:Object.fromEntries(Object.entries(x.properties).filter(([,v])=>v!==null).sort(([a],[b])=>a.localeCompare(b)))})).sort();
      assert.deepEqual(canonical(decoded),canonical(features));
      const their = official.serialize(collection);
      const theirsRead = JSON.parse(api.decode(their));
      assert.deepEqual(canonical(theirsRead.features),canonical(features));
      checks+=3;
      if (features.length > 100) {
        const bbox={minX:10,minY:1,maxX:30,maxY:4};
        const expected=features.filter(f=>f.geometry.coordinates[0]>=10&&f.geometry.coordinates[0]<=30&&f.geometry.coordinates[1]>=1&&f.geometry.coordinates[1]<=4);
        const ours=JSON.parse(api.query(own,JSON.stringify({min_x:10,min_y:1,max_x:30,max_y:4}))).features;
        assert.deepEqual(canonical(ours),canonical(expected));
        if (indexed) {
          const independent=await Array.fromAsync(official.deserialize(own,bbox));
          assert.deepEqual(canonical(independent),canonical(expected));
          checks++;
        }
        checks++;
      }
    }
  }
  console.log(`Interoperability: ${checks} independent comparisons passed`);
}
main().catch(e=>{console.error(e);process.exitCode=1});
