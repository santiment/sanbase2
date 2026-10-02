/**
 * GraphiQL fetcher for the Santiment API.
 *
 * - Returns an Observable instead of a Promise. GraphiQL's Stop button can
 *   only unsubscribe from Observables (for a Promise it just hides the
 *   spinner), so unsubscribing here aborts the HTTP request.
 * - Non-JSON responses (proxy error pages, timeouts) are turned into a
 *   GraphQL-shaped error with the HTTP status and a text snippet, instead of
 *   a "Unexpected token <" JSON parse error.
 * - History recording wraps this fetcher (withHistory in
 *   graphiql-history-store.js); this module only does HTTP.
 *
 * No React/GraphiQL imports, so it can be unit-tested in node.
 */
import { truncate } from "./graphiql-history-utils.js";

var BODY_SNIPPET_LENGTH = 300;

function defaultFetch(url, init) {
  return fetch(url, init);
}

// Readable text from an error body: <head>, scripts, tags and repeated
// whitespace stripped (the <title> usually just repeats the <h1>).
export function bodySnippet(text) {
  var plain = (text || "")
    .replace(/<(head|script|style)[\s\S]*?<\/\1>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  return truncate(plain, BODY_SNIPPET_LENGTH);
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
  var isGraphQL = !!json && typeof json === "object" && !Array.isArray(json) &&
    ("data" in json || "errors" in json);
  return isGraphQL ? json : httpError(status, statusText, text);
}

// POST a GraphQL request; resolves to a GraphQL result (never rejects for
// HTTP errors, only for network failures and aborts). `headers` is an object,
// as parsed by GraphiQL from the headers editor.
function post(fetchImpl, endpoint, params, headers, signal) {
  return fetchImpl(endpoint, {
    method: "POST",
    headers: Object.assign({ "Accept": "application/json", "Content-Type": "application/json" }, headers),
    body: JSON.stringify(params),
    credentials: "same-origin",
    signal: signal,
  }).then(function (response) {
    return response.text().then(function (text) {
      return parseResponse(response.status, response.statusText, text);
    });
  });
}

// options: { endpoint, fetchImpl }
export function createFetcher(options) {
  var endpoint = options.endpoint;
  var fetchImpl = options.fetchImpl || defaultFetch;

  return function fetcher(graphQLParams, fetcherOpts) {
    return {
      // GraphiQL always subscribes with an { next, error, complete } object.
      subscribe: function (observer) {
        var controller = new AbortController();
        var done = false;

        function deliver(result) {
          if (done) return; // unsubscribed (aborted) or already delivered
          done = true;
          if (observer.next) observer.next(result);
          if (observer.complete) observer.complete();
        }

        post(fetchImpl, endpoint, graphQLParams, fetcherOpts && fetcherOpts.headers, controller.signal)
          .then(deliver, function (error) {
            deliver({ errors: [{ message: "Network error: " + ((error && error.message) || String(error)) }] });
          });

        return {
          unsubscribe: function () {
            if (done) return;
            done = true;
            controller.abort();
          },
        };
      },
    };
  };
}

// Plain request for internal lookups (e.g. autocomplete data). Not recorded
// in history. Resolves to `data`; rejects on any GraphQL error, so callers
// never cache a partial result as if it were complete.
// options: { endpoint, fetchImpl, getHeaders }
export function createRequest(options) {
  var endpoint = options.endpoint;
  var fetchImpl = options.fetchImpl || defaultFetch;
  var getHeaders = options.getHeaders || function () { return null; };

  return function request(query, variables) {
    var params = variables ? { query: query, variables: variables } : { query: query };
    return Promise.resolve()
      .then(function () { return post(fetchImpl, endpoint, params, getHeaders()); })
      .then(function (result) {
        if (result.errors && result.errors.length) throw new Error(result.errors[0].message);
        return result.data || {};
      });
  };
}
