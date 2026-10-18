const assert=require('node:assert/strict');
const http=require('node:http');
const api=require('./api.cjs');
const {queryRemote}=require('./remote.cjs');

async function main(){
  const features=Array.from({length:1000},(_,id)=>({type:'Feature',geometry:{type:'Point',coordinates:[id,id%7]},properties:{id}}));
  const bytes=api.encode(JSON.stringify({type:'FeatureCollection',features}),true);
  const requests=[];
  let mode='good';
  const server=http.createServer((req,res)=>{
    requests.push({range:req.headers.range,match:req.headers['if-match']});
    const m=/^bytes=(\d+)-(\d+)$/.exec(req.headers.range||'');
    if(!m){res.writeHead(400).end();return;}
    let start=Number(m[1]),end=Number(m[2]);
    if(mode==='ignored'){res.writeHead(200).end(bytes);return;}
    if(mode==='encoding'){res.writeHead(206,{'content-encoding':'gzip'}).end();return;}
    let etag='"fixture-v1"';
    if(mode==='stale'&&requests.length>1)etag='"fixture-v2"';
    if(mode==='short')end--;
    res.writeHead(206,{'Content-Range':`bytes ${start}-${end}/${bytes.length}`,'ETag':etag,'Content-Length':end-start+1});
    res.end(bytes.subarray(start,end+1));
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const url=`http://127.0.0.1:${server.address().port}/data.fgb`;
  const bounds={min_x:100,min_y:0,max_x:110,max_y:6};
  try{
    const result=await queryRemote(url,bounds);
    assert.equal(result.data.features.length,11);
    assert.equal(result.stats.features_decoded,11);
    assert.ok(result.stats.received_bytes<bytes.length/4);
    assert.ok(requests.slice(1).every(r=>r.match==='"fixture-v1"'));
    for(const bad of ['ignored','encoding','stale','short']){
      mode=bad;requests.length=0;
      await assert.rejects(()=>queryRemote(url,bounds));
    }
    console.log(`HTTP acceptance: ${JSON.stringify(result.stats)}; file_bytes=${bytes.length}; 4 failure modes rejected`);
  }finally{await new Promise(resolve=>server.close(resolve));}
}
main().catch(e=>{console.error(e);process.exitCode=1;});
