/* Independent official generated FlatBuffers classes, including fields that
   the upstream GeoJSON/GDAL adapters cannot represent (T/TM and local schemas). */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const api = require('./api.cjs');
const {queryNativeRemote} = require('./remote.cjs');

async function main() {
  const {Builder, ByteBuffer} = await import('flatbuffers');
  const {Header:H} = await import('flatgeobuf/lib/mjs/flat-geobuf/header.js');
  const {Feature:F} = await import('flatgeobuf/lib/mjs/flat-geobuf/feature.js');
  const {Geometry:G} = await import('flatgeobuf/lib/mjs/flat-geobuf/geometry.js');
  const {Column:C} = await import('flatgeobuf/lib/mjs/flat-geobuf/column.js');
  const {Crs:R} = await import('flatgeobuf/lib/mjs/flat-geobuf/crs.js');
  const present = (table, field) => table.bb.__offset(table.bb_pos, 4+field*2) !== 0;
  const normal = n => Number.isNaN(n)?'NaN':n===Infinity?'Infinity':n===-Infinity?'-Infinity':Object.is(n,-0)?'-0':n;
  function vec(table, name, field) {
    return present(table,field) ? Array.from({length:table[`${name}Length`]()},(_,i)=>normal(table[name](i))) : null;
  }
  function columns(table, field) {
    if(!present(table,field))return null;
    return Array.from({length:table.columnsLength()},(_,i)=>{
      const c=table.columns(i);
      return [c.name(),c.type(),c.title(),c.description(),c.width(),c.precision(),c.scale(),c.nullable(),c.unique(),c.primaryKey(),c.metadata()];
    });
  }
  function geometry(g) {
    if(!g)return null;
    return {type:g.type(),ends:vec(g,'ends',0),xy:vec(g,'xy',1),z:vec(g,'z',2),m:vec(g,'m',3),t:vec(g,'t',4),
      tm:present(g,5)?Array.from({length:g.tmLength()},(_,i)=>g.tm(i).toString()):null,
      parts:present(g,7)?Array.from({length:g.partsLength()},(_,i)=>geometry(g.parts(i))):null};
  }
  function properties(f, schema) {
    const raw=Buffer.from(f.propertiesArray()||[]), values=Array((schema||[]).length).fill(null);
    let at=0;
    while(at<raw.length){
      const key=raw.readUInt16LE(at);at+=2;
      const code=schema[key][1];
      const readers={0:['readInt8',1],1:['readUInt8',1],2:['readUInt8',1],3:['readInt16LE',2],4:['readUInt16LE',2],5:['readInt32LE',4],6:['readUInt32LE',4],7:['readBigInt64LE',8],8:['readBigUInt64LE',8],9:['readFloatLE',4],10:['readDoubleLE',8]};
      if(code<=10){const [method,width]=readers[code];const n=raw[method](at);values[key]=typeof n==='bigint'?n.toString():normal(n);at+=width;}
      else {const length=raw.readUInt32LE(at);at+=4;values[key]=code===14?raw.subarray(at,at+length).toString('hex'):raw.subarray(at,at+length).toString('utf8');at+=length;}
    }
    return values;
  }
  function snapshot(bytes) {
    bytes=Buffer.from(bytes);
    const h=H.getSizePrefixedRootAsHeader(new ByteBuffer(new Uint8Array(bytes.subarray(8))));
    const global=columns(h,7),crs=h.crs();
    const header={name:h.name(),type:h.geometryType(),z:h.hasZ(),m:h.hasM(),t:h.hasT(),tm:h.hasTm(),
      envelope:vec(h,'envelope',1),columns:global,count:h.featuresCount().toString(),index:h.indexNodeSize(),
      crs:crs?[crs.org(),crs.code(),crs.name(),crs.description(),crs.wkt(),crs.codeString()]:null,
      title:h.title(),description:h.description(),metadata:h.metadata()};
    let at=12+bytes.readUInt32LE(8);
    if(header.index){let n=Number(h.featuresCount()),total=n;do{n=Math.ceil(n/header.index);total+=n;}while(n>1);at+=total*40;}
    const features=[];
    while(at<bytes.length){const size=bytes.readUInt32LE(at);const f=F.getSizePrefixedRootAsFeature(new ByteBuffer(new Uint8Array(bytes.subarray(at,at+4+size))));const local=columns(f,2);features.push({geometry:geometry(f.geometry()),columns:local,properties:properties(f,local??global)});at+=4+size;}
    assert.equal(at,bytes.length);
    return {header,features};
  }
  function makeColumns(b,values){
    if(values===null)return 0;
    const offsets=values.map(c=>{
      const strings={};for(const k of ['name','title','description','metadata'])if(c[k]!=null)strings[k]=b.createString(c[k]);
      C.startColumn(b);C.addName(b,strings.name);C.addType(b,c.type);
      for(const [key,set] of [['title','addTitle'],['description','addDescription'],['metadata','addMetadata']])if(strings[key])C[set](b,strings[key]);
      C.addWidth(b,c.width??-1);C.addPrecision(b,c.precision??-1);C.addScale(b,c.scale??-1);
      C.addNullable(b,c.nullable??true);C.addUnique(b,c.unique??false);C.addPrimaryKey(b,c.primary??false);
      return C.endColumn(b);
    });
    return H.createColumnsVector(b,offsets);
  }
  function makeGeometry(b,g,mask){
    if(g===null)return 0;
    const vectors={};
    if(g.xy!==undefined){vectors.xy=G.createXyVector(b,g.xy);const n=g.xy.length/2;
      if(mask&1)vectors.z=G.createZVector(b,Array.from({length:n},(_,i)=>i+.25));
      if(mask&2)vectors.m=G.createMVector(b,Array.from({length:n},(_,i)=>i+.5));
      if(mask&4)vectors.t=G.createTVector(b,Array.from({length:n},(_,i)=>2026+i/10));
      if(mask&8)vectors.tm=G.createTmVector(b,Array.from({length:n},(_,i)=>18446744073709551615n-BigInt(i)));
    }
    if(g.ends!==undefined)vectors.ends=G.createEndsVector(b,g.ends);
    if(g.parts!==undefined)vectors.parts=G.createPartsVector(b,g.parts.map(child=>makeGeometry(b,child,mask)));
    G.startGeometry(b);G.addType(b,g.type);
    for(const [key,set] of [['xy','addXy'],['z','addZ'],['m','addM'],['t','addT'],['tm','addTm'],['ends','addEnds'],['parts','addParts']])if(vectors[key])G[set](b,vectors[key]);
    return G.endGeometry(b);
  }
  function propertyBytes(schema,values){
    const out=[];
    for(let i=0;i<schema.length;i++){
      const value=values[i];if(value==null)continue;
      const code=schema[i].type, key=Buffer.alloc(2);key.writeUInt16LE(i);out.push(key);
      const methods={0:['writeInt8',1],1:['writeUInt8',1],2:['writeUInt8',1],3:['writeInt16LE',2],4:['writeUInt16LE',2],5:['writeInt32LE',4],6:['writeUInt32LE',4],7:['writeBigInt64LE',8],8:['writeBigUInt64LE',8],9:['writeFloatLE',4],10:['writeDoubleLE',8]};
      if(code<=10){const [method,width]=methods[code],data=Buffer.alloc(width);data[method](value);out.push(data);}
      else{const data=code===14?Buffer.from(value):Buffer.from(value,'utf8'),length=Buffer.alloc(4);length.writeUInt32LE(data.length);out.push(length,data);}
    }
    return Buffer.concat(out);
  }
  function makeFile(g,mask,mode,indexed=false,unknown=false,mixed=false){
    const global=mode===1?null:ALL_COLUMNS;
    const local=mode===0?null:mode===1?ALL_COLUMNS:mode===2?[]:[{name:'replacement',type:11}];
    const effective=local??global;
    const values=mode===2?[]:mode===3?['local overrides global']:ALL_VALUES;
    const hb=new Builder(1024),names=['dataset','','description','{"source":"independent builder"}'].map(x=>hb.createString(x));
    const cols=makeColumns(hb,global),empty=hb.createString(''),wkt=hb.createString('LOCAL_CS["test"]');
    R.startCrs(hb);R.addOrg(hb,empty);R.addCode(hb,0);R.addName(hb,empty);R.addWkt(hb,wkt);const crs=R.endCrs(hb);
    const dimensions=2+[1,2,4,8].filter(x=>mask&x).length;
    const envelope=H.createEnvelopeVector(hb,[...Array(dimensions).fill(-1e20),...Array(dimensions).fill(1e20)]);
    H.startHeader(hb);H.addName(hb,names[0]);H.addTitle(hb,names[1]);H.addDescription(hb,names[2]);H.addMetadata(hb,names[3]);H.addCrs(hb,crs);H.addEnvelope(hb,envelope);
    H.addGeometryType(hb,mixed?0:g?.type??0);H.addHasZ(hb,!!(mask&1));H.addHasM(hb,!!(mask&2));H.addHasT(hb,!!(mask&4));H.addHasTm(hb,!!(mask&8));
    if(cols)H.addColumns(hb,cols);H.addFeaturesCount(hb,unknown?0n:1n);H.addIndexNodeSize(hb,indexed?16:0);const header=H.endHeader(hb);hb.prep(8,0);H.finishSizePrefixedHeaderBuffer(hb,header);
    const fb=new Builder(1024),geometry=makeGeometry(fb,g,mask),columns=makeColumns(fb,local),props=F.createPropertiesVector(fb,propertyBytes(effective,values));
    F.startFeature(fb);if(geometry)F.addGeometry(fb,geometry);if(columns)F.addColumns(fb,columns);F.addProperties(fb,props);const feature=F.endFeature(fb);fb.prep(8,0);F.finishSizePrefixedFeatureBuffer(fb,feature);
    const index=Buffer.alloc(indexed?80:0);
    if(indexed)for(let i=0;i<2;i++){for(const [j,value]of[-1e20,-1e20,1e20,1e20].entries())index.writeDoubleLE(value,i*40+j*8);index.writeBigUInt64LE(i===0?1n:0n,i*40+32);}
    return Buffer.concat([Buffer.from([0x66,0x67,0x62,3,0x66,0x67,0x62,1]),Buffer.from(hb.asUint8Array()),index,Buffer.from(fb.asUint8Array())]);
  }
  const ALL_COLUMNS=Array.from({length:15},(_,type)=>({name:`c${type}`,type,title:type%2?'':null,description:'字段',metadata:'{}',width:25,precision:6,scale:2,unique:true,primary:type===7}));
  const ALL_VALUES=[-128,255,1,-32768,65535,-2147483648,4294967295,-9223372036854775808n,18446744073709551615n,1.25,-2.5,'你好','{"x":[1,true]}','2026-11-10T00:00:00Z',Buffer.from([0,255,127])];
  const point={type:1,xy:[1,2]}, line={type:2,xy:[0,0,1,1]}, polygon={type:3,xy:[0,0,2,0,2,2,0,0]}, circle={type:8,xy:[0,0,1,1,2,0,1,-1,0,0]};
  const geometries=[point,line,polygon,{type:4,xy:[1,2,3,4]},{type:5,xy:[0,0,1,1,2,2,3,3],ends:[2,4]},
    {type:6,parts:[polygon]}, {type:7,parts:[point,{type:7,parts:[circle]}]},circle,
    {type:9,parts:[{type:2,xy:[0,0,1,0]},{type:8,xy:[1,0,2,1,3,0]}]},
    {type:10,parts:[circle]}, {type:11,parts:[line,circle]}, {type:12,parts:[polygon,{type:10,parts:[circle]}]},
    {type:15,parts:[polygon]}, {type:16,xy:[0,0,1,0,0,1,0,0,1,0,1,1,0,1,1,0],ends:[4,8]}, {type:17,xy:[0,0,1,0,0,1,0,0]}];
  let checks=0,streamChecks=0,remoteChecks=0,rejected=0;
  for(const g of geometries)for(let mask=0;mask<16;mask++)for(let mode=0;mode<4;mode++){
    const bytes=makeFile(g,mask,mode),output=api.native_transcode(bytes);
    assert.deepEqual(snapshot(output),snapshot(bytes),`geometry ${g.type}, dimensions ${mask}, schema ${mode}`);checks++;
    if(mode===1){assert.deepEqual(snapshot(api.native_stream_transcode(bytes,37)),snapshot(bytes));streamChecks++;}
  }
  for(const g of geometries)for(const mask of [0,15]){
    const bytes=makeFile(g,mask,1,true),output=api.native_transcode(bytes);
    assert.deepEqual(snapshot(output),snapshot(bytes));
    assert.deepEqual(snapshot(api.native_stream_transcode(bytes,13)),snapshot(bytes));streamChecks++;
    assert.equal(api.native_query_count(output,JSON.stringify({min_x:-10,min_y:-10,max_x:10,max_y:10})),1);checks+=2;
  }
  for(const g of geometries){
    const empty=[6,7,9,10,11,12,15].includes(g.type)?{type:g.type,parts:[]}:{type:g.type,xy:[]};
    for(const mask of [0,15]){const bytes=makeFile(empty,mask,2,false,true);assert.deepEqual(snapshot(api.native_transcode(bytes)),snapshot(bytes));checks++;}
  }
  for(const g of [null,{type:1,xy:[NaN,NaN]}]){
    const bytes=makeFile(g,0,0);assert.deepEqual(snapshot(api.native_transcode(bytes)),snapshot(bytes));checks++;
  }
  const first=makeFile(line,15,1,false,true,true), second=makeFile(circle,15,3,false,true,true);
  const mixed=Buffer.concat([first,second.subarray(12+second.readUInt32LE(8))]);
  assert.deepEqual(snapshot(api.native_transcode(mixed)),snapshot(mixed));checks++;
  assert.deepEqual(snapshot(api.native_stream_transcode(mixed,1)),snapshot(mixed));streamChecks++;

  const arc={type:8,xy:[0,0,1,2,2,0]};
  let served;
  const server=http.createServer((req,res)=>{
    const match=/^bytes=(\d+)-(\d+)$/.exec(req.headers.range||'');
    if(!match||Number(match[2])>=served.length){res.writeHead(416).end();return;}
    if(req.headers['if-match']&&req.headers['if-match']!=='"native-case"'){res.writeHead(412).end();return;}
    const start=Number(match[1]),end=Number(match[2]);
    res.writeHead(206,{'Content-Range':`bytes ${start}-${end}/${served.length}`,'Content-Length':end-start+1,ETag:'"native-case"'});
    res.end(served.subarray(start,end+1));
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  try {
    const url=`http://127.0.0.1:${server.address().port}/native.fgb`;
    for(const indexed of [false,true]) {
      served=makeFile(arc,15,1,indexed);
      for(const [box,count] of [[{min_x:2.1,min_y:0,max_x:2.2,max_y:2},1],[{min_x:20,min_y:20,max_x:21,max_y:21},0]]){
        const remote=await queryNativeRemote(url,box);
        const result=snapshot(remote.bytes);
        assert.equal(remote.stats.matched,count);
        assert.deepEqual(result.features,count?snapshot(served).features:[]);
        assert.deepEqual(result,snapshot(api.native_query(served,JSON.stringify(box))));
        remoteChecks++;
      }
    }
  } finally { await new Promise(resolve=>server.close(resolve)); }

  const malformed=[makeFile({type:1,xy:[0,1,2]},0,0),makeFile({type:13,xy:[0,0]},0,0),
    makeFile({type:7,parts:[{type:0,xy:[1,2]}]},0,0),makeFile({type:10,parts:[line]},0,0),
    makeFile({type:9,parts:[line,{type:2,xy:[3,4,5,6]}]},0,0)];
  const good=makeFile(arc,15,1,true);
  for(let i=0;i<good.length;i+=7)malformed.push(good.subarray(0,i));
  for(const bytes of malformed){assert.throws(()=>api.native_transcode(bytes),error=>error.cause!==undefined);rejected++;}
  const out=path.join(__dirname,'../artifacts/native-schema');fs.mkdirSync(out,{recursive:true});
  fs.writeFileSync(path.join(out,'curve-all-dimensions.fgb'),good);
  fs.writeFileSync(path.join(out,'curve-all-dimensions-moon.fgb'),api.native_transcode(good));
  const report={oracle:'flatgeobuf@4.4.0 generated FlatBuffers classes',geometry_types:geometries.map(g=>g.type),dimension_masks:16,schema_modes:4,comparisons:checks,stream_comparisons:streamChecks,http_comparisons:remoteChecks,malformed_rejected:rejected};
  const baseline=require('../docs/compatibility-baseline.json');
  assert.deepEqual(report.geometry_types,baseline.native_geometry_types);
  assert.equal(report.dimension_masks,2**baseline.native_dimension_flags.length);
  fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2)+'\n');
  console.log(`Native schema interoperability: ${checks} binary, ${streamChecks} streaming, ${remoteChecks} HTTP comparisons; ${rejected} malformed inputs rejected`);
}
main().catch(error=>{console.error(error);process.exitCode=1;});
