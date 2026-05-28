defmodule Sanbase.Knowledge.Reranker.LocalBge do
  @moduledoc """
  Reranker backed by a local BGE (or compatible) cross-encoder server
  exposed over HTTP. No network egress, no API key, predictable latency.

  Expects a POST endpoint that accepts:

      {"query": "...", "documents": ["...", "..."], "top_k": N,
       "return_documents": false}

  and returns either of the following result shapes (whichever the
  server emits — both are accepted transparently):

    * Cohere/Infinity-style wrapper: `{"results": [{"index": i,
      "relevance_score": s}, ...]}`
    * TEI-style flat array: `[{"index": i, "score": s}, ...]`

  Defaults to `http://localhost:8000/rerank`. Override via
  `Application.put_env(:sanbase, Sanbase.Knowledge.Reranker.LocalBge,
  url: "http://other-host:9000/rerank")` or by passing `url:` in opts.

  On any error returns `{:error, reason}` so the dispatcher in
  `Sanbase.Knowledge.Reranker` falls back to coarse order and the
  user-facing path never breaks.
  """

  @behaviour Sanbase.Knowledge.Reranker

  require Logger

  @default_url "http://localhost:8000/rerank"
  @default_timeout_ms 30_000
  @default_max_retries 1
  @max_candidate_chars 600

  @doc "Declares the candidate-text format style this backend wants."
  def style(), do: :cross_encoder

  @impl true
  def rerank(_query, [], _opts), do: {:ok, []}

  def rerank(query, candidates, opts) when is_binary(query) and is_list(candidates) do
    http_post = Keyword.get(opts, :http_post, &default_http_post/2)
    url = Keyword.get(opts, :url, default_url())
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    max_retries = Keyword.get(opts, :max_retries, @default_max_retries)

    body = build_request_body(query, candidates)
    headers = [{"Content-Type", "application/json"}]

    req_opts = [
      json: body,
      headers: headers,
      receive_timeout: timeout_ms,
      retry: :transient,
      max_retries: max_retries
    ]

    started_at = System.monotonic_time(:millisecond)

    case http_post.(url, req_opts) do
      {:ok, %{status: 200, body: response}} ->
        elapsed = System.monotonic_time(:millisecond) - started_at

        case parse_results(response) do
          {:ok, results} ->
            :telemetry.execute(
              [:sanbase, :knowledge, :rerank, :stop],
              %{duration_ms: elapsed, candidates: length(candidates)},
              %{model: "local-bge", source: opts[:source]}
            )

            {:ok, apply_results(candidates, results)}

          {:error, reason} = err ->
            Logger.warning("Reranker.LocalBge bad response: #{inspect(reason)}")
            err
        end

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Reranker.LocalBge HTTP #{status}: #{inspect(body)}")
        {:error, {:http_status, status}}

      {:error, reason} ->
        Logger.warning("Reranker.LocalBge transport error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Build the JSON body for the local rerank server.

  `top_k` is set to the candidate count so a score comes back for every
  candidate and we can return the full reordered list. `return_documents`
  is false because we already have them locally.
  """
  def build_request_body(query, candidates) do
    documents = Enum.map(candidates, fn c -> truncate(c.text) end)

    %{
      "query" => query,
      "documents" => documents,
      "top_k" => length(candidates),
      "return_documents" => false
    }
  end

  @doc """
  Reorder `candidates` by the relevance scores returned by the server.

  Accepts entries shaped `%{"index" => i, "relevance_score" => s}` or
  `%{"index" => i, "score" => s}` (string or atom keys). Indices out of
  range, duplicated, or missing are handled gracefully — missing
  candidates are appended in original order at the tail.

  Public for testing.
  """
  def apply_results(candidates, results) when is_list(candidates) and is_list(results) do
    indexed = Enum.with_index(candidates)
    max_idx = length(candidates) - 1

    {picked, seen} =
      results
      |> Enum.sort_by(&(-relevance_score(&1)))
      |> Enum.reduce({[], MapSet.new()}, fn r, {acc, seen} ->
        idx = index_of(r)

        cond do
          not is_integer(idx) ->
            {acc, seen}

          idx < 0 or idx > max_idx ->
            {acc, seen}

          MapSet.member?(seen, idx) ->
            {acc, seen}

          true ->
            {[Enum.at(candidates, idx) | acc], MapSet.put(seen, idx)}
        end
      end)

    tail =
      indexed
      |> Enum.reject(fn {_c, i} -> MapSet.member?(seen, i) end)
      |> Enum.map(fn {c, _i} -> c end)

    Enum.reverse(picked) ++ tail
  end

  # Private

  defp index_of(%{"index" => i}) when is_integer(i), do: i
  defp index_of(%{index: i}) when is_integer(i), do: i
  defp index_of(_), do: nil

  defp relevance_score(%{"relevance_score" => s}) when is_number(s), do: s
  defp relevance_score(%{relevance_score: s}) when is_number(s), do: s
  defp relevance_score(%{"score" => s}) when is_number(s), do: s
  defp relevance_score(%{score: s}) when is_number(s), do: s
  defp relevance_score(_), do: 0.0

  defp parse_results(%{"results" => results}) when is_list(results), do: {:ok, results}
  defp parse_results(results) when is_list(results), do: {:ok, results}
  defp parse_results(response), do: {:error, {:malformed_response, response}}

  defp truncate(text) when is_binary(text) do
    if String.length(text) <= @max_candidate_chars do
      text
    else
      String.slice(text, 0, @max_candidate_chars) <> "…"
    end
  end

  defp truncate(_), do: ""

  defp default_http_post(url, opts) do
    Req.post(url, opts)
  end

  defp default_url() do
    :sanbase
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:url, @default_url)
  end
end
