/**
 * GraphiQL fetcher for the Santiment API.
 *
 * - Returns an Observable instead of a Promise. GraphiQL's Stop button can
 *   only unsubscribe from Observables (for a Promise it just hides the
 *   spinner), so unsubscribing here aborts the HTTP request.
 * - Non-JSON responses (proxy error pages, timeouts) are turned into a
 *   GraphQL-shaped error with the HTTP status and a text snippet, instead of
 *   a "Unexpected token <" JSON parse error.
 * - User executions are recorded in the history store with status and
 *   duration; schema introspection is not.
 *
 * No React/GraphiQL imports, so it can be unit-tested in node.
 */
import { classifyResult, isIntrospectionCall } from "./graphiql-history-utils.js";

var BODY_SNIPPET_LENGTH = 300;

function mergeHeaders(fetcherOpts) {
  var headers = Object.create(null);
  headers["Accept"] = "application/json";
  headers["Content-Type"] = "application/json";

  if (fetcherOpts && fetcherOpts.headers) {
    try {
      var editorHeaders = typeof fetcherOpts.headers === "string"
        ? JSON.parse(fetcherOpts.headers)
        : fetcherOpts.headers;
      Object.keys(editorHeaders).forEach(function (key) {
        headers[key] = editorHeaders[key];
      });
    } catch (e) {
      // Invalid JSON in headers editor — ignore
    }
  }
  return headers;
}

function isGraphQLResponse(json) {
  return !!json && typeof json === "object" && !Array.isArray(json) &&
    ("data" in json || "errors" in json);
}

// Readable text from an error body: <head>, scripts, tags and repeated
// whitespace stripped (the <title> usually just repeats the <h1>).
export function bodySnippet(text) {
  var plain = (text || "")
    .replace(/<(head|script|style)[\s\S]*?<\/\1>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  return plain.length > BODY_SNIPPET_LENGTH
    ? plain.slice(0, BODY_SNIPPET_LENGTH - 1) + "…"
    : plain;
}

function httpError(status, statusText, text) {
  var label = "HTTP " + status + (statusText ? " " + statusText : "");
  var snippet = bodySnippet(text);
  return {
    errors: [{
      message: label + (snippet ? ": " + snippet : ": the server returned a non-GraphQL response"),
      extensions: { httpStatus: status },
    }],
  };
}

// Turn a fetch Response into a GraphQL result. A GraphQL-shaped JSON body is
// returned as-is whatever the status (the API reports errors that way);
// anything else becomes an error that names the HTTP status.
export function parseResponse(status, statusText, text) {
  var json;
  try {
    json = JSON.parse(text);
  } catch (e) {
    return httpError(status, statusText, text);
  }
  if (isGraphQLResponse(json)) return json;
  return httpError(status, statusText, text);
}

function isAbortError(error) {
  return !!error && (error.name === "AbortError" || error.code === 20);
}

// options: { endpoint, fetchImpl, historyStore, onHistoryError }
export function createFetcher(options) {
  var endpoint = options.endpoint;
  var fetchImpl = options.fetchImpl || function (url, init) { return fetch(url, init); };
  var historyStore = options.historyStore || null;
  var onHistoryError = options.onHistoryError || function () {};

  function startRun(graphQLParams, fetcherOpts) {
    if (!historyStore || isIntrospectionCall(graphQLParams, fetcherOpts)) return null;
    try {
      return historyStore.startRun(graphQLParams);
    } catch (e) {
      onHistoryError(e);
      return null;
    }
  }

  function finishRun(token, outcome) {
    if (!token) return;
    try {
      historyStore.finishRun(token, outcome);
    } catch (e) {
      onHistoryError(e);
    }
  }

  return function fetcher(graphQLParams, fetcherOpts) {
    return {
      subscribe: function (observerOrNext) {
        var observer = typeof observerOrNext === "function"
          ? { next: observerOrNext }
          : observerOrNext || {};
        var controller = typeof AbortController !== "undefined" ? new AbortController() : null;
        var done = false;
        var token = startRun(graphQLParams, fetcherOpts);

        function deliver(result) {
          if (done) return;
          done = true;
          finishRun(token, classifyResult(result));
          if (observer.next) observer.next(result);
          if (observer.complete) observer.complete();
        }

        fetchImpl(endpoint, {
          method: "POST",
          headers: mergeHeaders(fetcherOpts),
          body: JSON.stringify(graphQLParams),
          credentials: "same-origin",
          signal: controller ? controller.signal : undefined,
        })
          .then(function (response) {
            return response.text().then(function (text) {
              return parseResponse(response.status, response.statusText, text);
            });
          })
          .then(deliver, function (error) {
            if (done) return;
            if (isAbortError(error)) {
              // Cancelled by unsubscribe(); outcome already recorded there.
              done = true;
              return;
            }
            deliver({ errors: [{ message: "Network error: " + ((error && error.message) || String(error)) }] });
          });

        return {
          unsubscribe: function () {
            if (done) return;
            done = true;
            finishRun(token, { status: "cancelled", error: null });
            if (controller) controller.abort();
          },
        };
      },
    };
  };
}

// Plain request for internal lookups (e.g. autocomplete data). Not recorded
// in history. Resolves to `data`, rejects when the response has errors.
// options: { endpoint, fetchImpl, getHeaders }
export function createRequest(options) {
  var endpoint = options.endpoint;
  var fetchImpl = options.fetchImpl || function (url, init) { return fetch(url, init); };
  var getHeaders = options.getHeaders || function () { return null; };

  return function request(query, variables) {
    var params = { query: query };
    var op = /^\s*(?:query|mutation)\s+([_A-Za-z][_0-9A-Za-z]*)/.exec(query);
    if (op) params.operationName = op[1];
    if (variables) params.variables = variables;
    return Promise.resolve()
      .then(function () {
        return fetchImpl(endpoint, {
          method: "POST",
          headers: mergeHeaders({ headers: getHeaders() }),
          body: JSON.stringify(params),
          credentials: "same-origin",
        });
      })
      .then(function (response) {
        return response.text().then(function (text) {
          return parseResponse(response.status, response.statusText, text);
        });
      })
      .then(function (result) {
        if (result.errors && result.errors.length && !result.data) {
          throw new Error(result.errors[0].message);
        }
        return result.data || {};
      });
  };
}
