import { describe, it, expect, vi } from "vitest";
import { fetcherReturnToPromise, isObservable } from "@graphiql/toolkit";
import { createFetcher, parseResponse, bodySnippet } from "./graphiql-fetcher.js";
import { withHistory } from "./graphiql-history-store.js";

// The production composition: HTTP fetcher wrapped with history recording.
function recording(fetchImpl, history, onError) {
  return withHistory(createFetcher({ endpoint: "/graphql", fetchImpl: fetchImpl }), history, onError);
}

function response(status, text, statusText) {
  return { status: status, statusText: statusText || "", text: function () { return Promise.resolve(text); } };
}

// fetch double that resolves on demand and rejects with AbortError on abort
function controllableFetch() {
  var calls = [];
  var impl = vi.fn(function (url, init) {
    return new Promise(function (resolve, reject) {
      var call = { url: url, init: init, resolve: resolve, reject: reject, aborted: false };
      calls.push(call);
      if (init.signal) {
        init.signal.addEventListener("abort", function () {
          call.aborted = true;
          var err = new Error("The operation was aborted.");
          err.name = "AbortError";
          reject(err);
        });
      }
    });
  });
  impl.calls = calls;
  return impl;
}

function fakeHistory() {
  var finished = [];
  var started = [];
  return {
    started: started,
    finished: finished,
    startRun: function (p) { started.push(p); return { id: "t" + started.length }; },
    finishRun: function (token, outcome) { finished.push([token.id, outcome]); },
  };
}

function run(fetcher, params, opts) {
  return new Promise(function (resolve) {
    var events = [];
    var sub = fetcher(params, opts).subscribe({
      next: function (v) { events.push(["next", v]); },
      error: function (e) { events.push(["error", e]); resolve(events); },
      complete: function () { events.push(["complete"]); resolve(events); },
    });
    events.sub = sub;
  });
}

var flush = function () { return new Promise(function (r) { setTimeout(r, 0); }); };
var EXEC_OPTS = { headers: {}, documentAST: undefined };

describe("createFetcher", function () {
  it("returns an Observable (so GraphiQL's Stop can unsubscribe)", function () {
    var fetcher = createFetcher({ endpoint: "/graphql", fetchImpl: controllableFetch() });
    expect(isObservable(fetcher({ query: "{ a }" }, EXEC_OPTS))).toBe(true);
  });

  it("delivers the result then completes", async function () {
    var f = controllableFetch();
    var fetcher = createFetcher({ endpoint: "/graphql", fetchImpl: f });
    var p = run(fetcher, { query: "{ a }" }, EXEC_OPTS);
    await flush();
    f.calls[0].resolve(response(200, '{"data":{"a":1}}'));
    var events = await p;
    expect(events.slice()).toEqual([["next", { data: { a: 1 } }], ["complete"]]);
  });

  it("aborts the HTTP request on unsubscribe and records it as cancelled", async function () {
    var f = controllableFetch();
    var history = fakeHistory();
    var fetcher = recording(f, history);
    var next = vi.fn();
    var sub = fetcher({ query: "{ slow }" }, EXEC_OPTS).subscribe({ next: next });
    await flush();
    sub.unsubscribe();
    await flush();
    expect(f.calls[0].aborted).toBe(true);
    expect(next).not.toHaveBeenCalled();
    expect(history.finished).toEqual([["t1", { status: "cancelled", error: null }]]);
  });

  it("unsubscribe after completion does not abort or re-record", async function () {
    var f = controllableFetch();
    var history = fakeHistory();
    var fetcher = recording(f, history);
    var p = run(fetcher, { query: "{ a }" }, EXEC_OPTS);
    await flush();
    f.calls[0].resolve(response(200, '{"data":{"a":1}}'));
    var events = await p;
    events.sub.unsubscribe();
    expect(f.calls[0].aborted).toBe(false);
    expect(history.finished.length).toBe(1);
    expect(history.finished[0][1].status).toBe("success");
  });

  it("records an error outcome when the wrapped fetcher errors", function () {
    var history = fakeHistory();
    var failing = function () {
      return { subscribe: function (o) { o.error(new Error("boom")); return { unsubscribe: function () {} }; } };
    };
    var error = vi.fn();
    withHistory(failing, history)({ query: "{ a }" }, EXEC_OPTS).subscribe({ error: error });
    expect(error).toHaveBeenCalled();
    expect(history.finished).toEqual([["t1", { status: "error", error: "boom" }]]);
  });

  it("works with fetcherReturnToPromise (used for introspection)", async function () {
    var f = controllableFetch();
    var history = fakeHistory();
    var fetcher = recording(f, history);
    var p = fetcherReturnToPromise(fetcher({ query: "query IntrospectionQuery { __schema { types { name } } }", operationName: "IntrospectionQuery" }, {}));
    await flush();
    f.calls[0].resolve(response(200, '{"data":{"__schema":{}}}'));
    expect(await p).toEqual({ data: { __schema: {} } });
    expect(f.calls[0].aborted).toBe(false);
    expect(history.started.length).toBe(0); // introspection is not history
  });

  it("turns an HTML error page into a readable error", async function () {
    var f = controllableFetch();
    var history = fakeHistory();
    var fetcher = recording(f, history);
    var p = run(fetcher, { query: "{ a }" }, EXEC_OPTS);
    await flush();
    f.calls[0].resolve(response(502, "<html><head><title>502</title><style>b{}</style></head><body><h1>502 Bad Gateway</h1><hr>nginx</body></html>", "Bad Gateway"));
    var events = await p;
    var result = events[0][1];
    expect(result.errors[0].message).toBe("HTTP 502 Bad Gateway: 502 Bad Gateway nginx");
    expect(result.errors[0].extensions.httpStatus).toBe(502);
    expect(history.finished[0][1].status).toBe("error");
  });

  it("passes GraphQL-shaped JSON through regardless of status", async function () {
    var f = controllableFetch();
    var fetcher = createFetcher({ endpoint: "/graphql", fetchImpl: f });
    var p = run(fetcher, { query: "{ a }" }, EXEC_OPTS);
    await flush();
    f.calls[0].resolve(response(429, '{"errors":[{"message":"API Rate Limit Reached"}]}'));
    var events = await p;
    expect(events[0][1]).toEqual({ errors: [{ message: "API Rate Limit Reached" }] });
  });

  it("reports network failures", async function () {
    var f = controllableFetch();
    var fetcher = createFetcher({ endpoint: "/graphql", fetchImpl: f });
    var p = run(fetcher, { query: "{ a }" }, EXEC_OPTS);
    await flush();
    f.calls[0].reject(new TypeError("Failed to fetch"));
    var events = await p;
    expect(events[0][1].errors[0].message).toBe("Network error: Failed to fetch");
  });

  it("merges editor headers and sends credentials", async function () {
    var f = controllableFetch();
    var fetcher = createFetcher({ endpoint: "/graphql", fetchImpl: f });
    fetcher({ query: "{ a }" }, { headers: { Authorization: "Apikey x" }, documentAST: undefined }).subscribe({});
    await flush();
    var init = f.calls[0].init;
    expect(init.headers.Authorization).toBe("Apikey x");
    expect(init.headers["Content-Type"]).toBe("application/json");
    expect(init.credentials).toBe("same-origin");
    expect(JSON.parse(init.body)).toEqual({ query: "{ a }" });
  });

  it("works without editor headers (introspection passes none)", async function () {
    var f = controllableFetch();
    var fetcher = createFetcher({ endpoint: "/graphql", fetchImpl: f });
    fetcher({ query: "{ a }" }, {}).subscribe({});
    await flush();
    expect(f.calls[0].init.headers).toEqual({ Accept: "application/json", "Content-Type": "application/json" });
  });

  it("keeps executing when the history store throws", async function () {
    var f = controllableFetch();
    var onHistoryError = vi.fn();
    var broken = {
      startRun: function () { throw new Error("quota"); },
      finishRun: function () { throw new Error("quota"); },
    };
    var fetcher = recording(f, broken, onHistoryError);
    var p = run(fetcher, { query: "{ a }" }, EXEC_OPTS);
    await flush();
    f.calls[0].resolve(response(200, '{"data":{"a":1}}'));
    var events = await p;
    expect(events[0][1]).toEqual({ data: { a: 1 } });
    expect(onHistoryError).toHaveBeenCalledTimes(1); // startRun failed -> no token -> no finishRun
  });
});

describe("parseResponse", function () {
  it("errors on JSON that is not a GraphQL response", function () {
    var r = parseResponse(500, "Internal Server Error", '{"message":"boom"}');
    expect(r.errors[0].message).toBe('HTTP 500 Internal Server Error: {"message":"boom"}');
  });

  it("errors on an empty body", function () {
    expect(parseResponse(504, "Gateway Timeout", "").errors[0].message)
      .toBe("HTTP 504 Gateway Timeout: the server returned a non-GraphQL response");
  });
});

describe("bodySnippet", function () {
  it("strips tags, scripts and whitespace and truncates", function () {
    expect(bodySnippet("<p>a</p>\n\n<script>x()</script><b>b</b>")).toBe("a b");
    expect(bodySnippet("x".repeat(1000)).length).toBe(300);
  });
});
