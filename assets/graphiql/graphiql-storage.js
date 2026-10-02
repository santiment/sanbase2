/**
 * Guarded localStorage access. Every call can throw (private mode, blocked
 * site data, quota), so reads fall back to null and writes report success.
 */

export function defaultStorage() {
  try {
    return typeof localStorage !== "undefined" ? localStorage : null;
  } catch (e) {
    return null;
  }
}

// Raw string, or null when missing or unreadable.
export function readRaw(storage, key) {
  if (!storage) return null;
  try {
    return storage.getItem(key);
  } catch (e) {
    return null;
  }
}

export function parseJson(raw) {
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch (e) {
    return null;
  }
}

export function readJson(storage, key) {
  return parseJson(readRaw(storage, key));
}

// Returns true when the value was stored.
export function writeRaw(storage, key, raw) {
  if (!storage) return false;
  try {
    storage.setItem(key, raw);
    return true;
  } catch (e) {
    return false;
  }
}

export function writeJson(storage, key, value) {
  return writeRaw(storage, key, JSON.stringify(value));
}

// --- Swappable storage backends ---------------------------------------------
//
// History and the autocomplete cache persist through this async key-value
// interface, so the browser storage behind them can be swapped in one place
// (graphiql.js). Small UI preferences that must be read before the first
// paint (tab names, sort order) use the synchronous helpers above instead.
//
// A backend stores JSON-serializable values:
//   get(key)                -> Promise<value | null>   (null when missing or unreadable)
//   set(key, value)         -> Promise<void>           (rejects when it cannot store: quota, blocked)
//   remove(key)             -> Promise<void>
//   onChange(key, listener) -> unsubscribe function; listener(value) is called
//                              when another browser tab changes `key`

export function localStorageBackend(storage) {
  var ls = storage !== undefined ? storage : defaultStorage();

  return {
    get: function (key) {
      return Promise.resolve(readJson(ls, key));
    },
    set: function (key, value) {
      return writeJson(ls, key, value)
        ? Promise.resolve()
        : Promise.reject(new Error("localStorage refused to store " + key));
    },
    remove: function (key) {
      try {
        if (ls) ls.removeItem(key);
      } catch (e) {
        // already unreadable; nothing to remove
      }
      return Promise.resolve();
    },
    onChange: function (key, listener) {
      if (typeof window === "undefined") return function () {};
      function onStorage(e) {
        // e.key is null when another tab calls localStorage.clear()
        if (e.key === key || e.key === null) listener(parseJson(e.newValue));
      }
      window.addEventListener("storage", onStorage);
      return function () { window.removeEventListener("storage", onStorage); };
    },
  };
}

// In-memory backend: nothing survives a reload. For tests, and as the
// fallback when no browser storage is available. Values are copied through
// JSON like a real store would.
export function memoryBackend() {
  var data = new Map();
  return {
    get: function (key) {
      return Promise.resolve(data.has(key) ? JSON.parse(data.get(key)) : null);
    },
    set: function (key, value) {
      data.set(key, JSON.stringify(value));
      return Promise.resolve();
    },
    remove: function (key) {
      data.delete(key);
      return Promise.resolve();
    },
    onChange: function () {
      return function () {};
    },
  };
}
