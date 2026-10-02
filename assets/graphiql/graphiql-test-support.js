/**
 * Test helpers (imported by *.test.js only, never bundled).
 */

// Fake Web Storage (what localStorageBackend wraps). Set `failures` to make
// the next N setItem calls throw like a full quota (Infinity: always).
export function fakeLocalStorage(initial) {
  var data = Object.assign({}, initial || {});
  return {
    data: data,
    failures: 0,
    getItem: function (k) { return Object.prototype.hasOwnProperty.call(data, k) ? data[k] : null; },
    setItem: function (k, v) {
      if (this.failures > 0) {
        this.failures--;
        throw new Error("QuotaExceededError");
      }
      data[k] = String(v);
    },
    removeItem: function (k) { delete data[k]; },
  };
}
