const assert = require('node:assert/strict');
const http = require('node:http');
const {queryRemote} = require('./remote.cjs');
const bounds = {min_x:0, min_y:0, max_x:1, max_y:1};

async function main() {
  let fetchCalls = 0;
  const cancelled = new AbortController();
  cancelled.abort();
  await assert.rejects(queryRemote('https://unused.invalid', bounds, {
    signal:cancelled.signal, fetch:() => { fetchCalls++; throw new Error('must not fetch'); },
  }), {name:'AbortError'});
  assert.equal(fetchCalls, 0);
  for (const timeoutMs of [0, -1, 1.5, Infinity, 2147483648]) {
    await assert.rejects(queryRemote('https://unused.invalid', bounds, {timeoutMs}), RangeError);
  }

  // Verify rejected response bodies are explicitly cancelled without reading.
  for (const headers of [{'Content-Encoding':'gzip'}, {'Content-Length':'999'}]) {
    let cleaned = false;
    const fetch = async () => new Response(new ReadableStream({
      cancel() { cleaned = true; },
    }), {status:206, headers});
    await assert.rejects(queryRemote('https://unused.invalid', bounds, {fetch}));
    assert.ok(cleaned, 'rejected response body must be cancelled');
  }

  // A live socket stalls during a range response; both user cancel and deadline
  // must abort body consumption, without waiting for a complete feature.
  let onRequest;
  const server = http.createServer((req, res) => {
    res.writeHead(206, {'Content-Range':'bytes 0-11/100', ETag:'"stall"'});
    res.write(Buffer.from([0x66]));
    onRequest?.();
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const url = `http://127.0.0.1:${server.address().port}/stall.fgb`;
  try {
    const controller = new AbortController();
    onRequest = () => controller.abort();
    await assert.rejects(queryRemote(url, bounds, {signal:controller.signal}), {name:'AbortError'});
    onRequest = undefined;
    await assert.rejects(queryRemote(url, bounds, {timeoutMs:50}),
      error => ['AbortError', 'TimeoutError'].includes(error.name));
  } finally {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
  console.log('Remote lifecycle: pre-cancel, invalid deadlines, body cleanup, live cancel and live timeout passed');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
