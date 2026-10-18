const api = require('./api.cjs');

async function queryRemote(url, bounds, options = {}) {
  const session = api.start_remote(JSON.stringify(bounds));
  const fetch_ = options.fetch || globalThis.fetch;
  let validator;
  const deadline = AbortSignal.timeout(options.timeoutMs || 30000);
  for (;;) {
    const request = JSON.parse(api.next_remote(session));
    if (!request) break;
    const end = request.start + request.length - 1;
    const headers = {Range:`bytes=${request.start}-${end}`,'Accept-Encoding':'identity'};
    if (validator) headers['If-Match'] = validator;
    const response = await fetch_(url,{headers,signal:deadline,redirect:'error'});
    const encoding=response.headers.get('content-encoding');
    if (encoding && encoding !== 'identity') throw new Error('Encoded HTTP bodies invalidate byte offsets');
    if (response.status !== 206) { await response.body?.cancel(); throw new Error(`Expected HTTP 206, got ${response.status}`); }
    const parts=[];
    let length=0;
    for await (const part of response.body) {
      length+=part.length;
      if (length>request.length) throw new Error('Range response exceeded requested length');
      parts.push(part);
    }
    const data=Buffer.concat(parts,length);
    const etag=response.headers.get('etag') || '';
    api.accept_remote(session,response.status,response.headers.get('content-range') || '',etag,data);
    validator=etag;
  }
  return {data:JSON.parse(api.result_remote(session)),stats:JSON.parse(api.stats_remote(session))};
}
module.exports={queryRemote};
