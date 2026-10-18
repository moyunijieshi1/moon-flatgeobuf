const raw = require('../_build/js/debug/build/host/host.js');
// Compiler-specific Result lowering is deliberately confined to this adapter.
function unwrap(result) {
  if (result?.$tag !== 1) {
    const e = new Error(JSON.stringify(result?._0 ?? result));
    e.cause = result;
    throw e;
  }
  return result._0;
}
module.exports = new Proxy({}, {
  get(_, key) {
    if (typeof raw[key] !== 'function') return undefined;
    if (key === 'stats_remote' || key === 'report') return (...args) => raw[key](...args);
    return (...args) => unwrap(raw[key](...args));
  }
});
