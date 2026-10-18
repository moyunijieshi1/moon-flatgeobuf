#!/usr/bin/env node
const fs = require('node:fs');
const api = require('./api.cjs');
const {queryRemote} = require('./remote.cjs');

const usage=`Moon FlatGeobuf
  node scripts/cli.cjs encode input.geojson output.fgb [--no-index]
  node scripts/cli.cjs decode input.fgb output.geojson
  node scripts/cli.cjs inspect input.fgb
  node scripts/cli.cjs validate input.fgb
  node scripts/cli.cjs query input.fgb minX minY maxX maxY output.geojson
  node scripts/cli.cjs remote URL minX minY maxX maxY output.geojson
Build the MoonBit JavaScript host first: moon build --target js`;

function bounds(args) {
  const numbers=args.map(Number);
  if(numbers.length!==4||numbers.some(x=>!Number.isFinite(x)))throw new Error('Four finite bounds are required');
  return Object.fromEntries(['min_x','min_y','max_x','max_y'].map((k,i)=>[k,numbers[i]]));
}
function writeNew(file,bytes) {fs.writeFileSync(file,bytes,{flag:'wx'});}
async function main() {
  const [command,...args]=process.argv.slice(2);
  if(!command||command==='--help'){console.log(usage);return;}
  if(command==='encode'&&(args.length===2||(args.length===3&&args[2]==='--no-index'))){
    writeNew(args[1],api.encode(fs.readFileSync(args[0],'utf8'),!args.includes('--no-index')));
  }else if(command==='decode'&&args.length===2){
    writeNew(args[1],api.decode(fs.readFileSync(args[0]))+'\n');
  }else if(command==='inspect'&&args.length===1){
    console.log(JSON.stringify(JSON.parse(api.summary(fs.readFileSync(args[0]))),null,2));
  }else if(command==='validate'&&args.length===1){
    const report=JSON.parse(api.report(fs.readFileSync(args[0])));
    console.log(JSON.stringify(report,null,2));
    if(!report.valid)process.exitCode=2;
  }else if(command==='query'&&args.length===6){
    const box=bounds(args.slice(1,5));
    writeNew(args[5],api.query(fs.readFileSync(args[0]),JSON.stringify(box))+'\n');
  }else if(command==='remote'&&args.length===6){
    const result=await queryRemote(args[0],bounds(args.slice(1,5)));
    writeNew(args[5],JSON.stringify(result.data)+'\n');
    console.error(JSON.stringify(result.stats));
  }else{throw new Error(usage);}
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
