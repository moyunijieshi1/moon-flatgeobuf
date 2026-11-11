const api = require('./api.cjs');

async function query(url, bounds, options, suffix) {
  const timeoutMs = options.timeoutMs ?? 30000;
  if (!Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 2147483647) {
    throw new RangeError('timeoutMs must be a positive integer up to 2147483647');
  }
  // A superseded map viewport can cancel both the fetch and an in-flight body.
  const deadline = AbortSignal.timeout(timeoutMs);
  const signal = options.signal ? AbortSignal.any([deadline, options.signal]) : deadline;
  signal.throwIfAborted();
  const session = api[`start_${suffix}`](JSON.stringify(bounds));
  const fetch_ = options.fetch || globalThis.fetch;
  let validator;
  for (;;) {
    signal.throwIfAborted();
    const request = JSON.parse(api[`next_${suffix}`](session));
    if (!request) break;
    const end = request.start + request.length - 1;
    const headers = {Range:`bytes=${request.start}-${end}`,'Accept-Encoding':'identity'};
    if (validator) headers['If-Match'] = validator;
    const response = await fetch_(url,{headers,signal,redirect:'error'});
    const encoding=response.headers.get('content-encoding');
    if (encoding && encoding !== 'identity') {
      await response.body?.cancel();
      throw new Error('Encoded HTTP bodies invalidate byte offsets');
    }
    if (response.status !== 206) { await response.body?.cancel(); throw new Error(`Expected HTTP 206, got ${response.status}`); }
    const parts=[];
    let length=0;
    const declaredLength = response.headers.get('content-length');
    if (declaredLength !== null && (!/^\d+$/.test(declaredLength) || Number(declaredLength) !== request.length)) {
      await response.body?.cancel();
      throw new Error('Content-Length does not match the requested range');
    }
    for await (const part of response.body) {
      signal.throwIfAborted();
      length+=part.length;
      if (length>request.length) throw new Error('Range response exceeded requested length');
      parts.push(part);
    }
    const data=Buffer.concat(parts,length);
    const etag=response.headers.get('etag') || '';
    api[`accept_${suffix}`](session,response.status,response.headers.get('content-range') || '',etag,data);
    validator=etag;
  }
  return {result:api[`result_${suffix}`](session),stats:JSON.parse(api[`stats_${suffix}`](session))};
}
async function queryRemote(url, bounds, options = {}) {
  const {result,stats}=await query(url,bounds,options,'remote');
  return {geojson:result,stats};
}
async function queryNativeRemote(url, bounds, options = {}) {
  const {result,stats}=await query(url,bounds,options,'native_remote');
  return {bytes:result,stats};
}
module.exports={queryRemote,queryNativeRemote};
