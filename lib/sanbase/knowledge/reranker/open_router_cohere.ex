defmodule Sanbase.Knowledge.Reranker.OpenRouterCohere do
  @moduledoc """
  Reranker backed by Cohere's `rerank-v3.5` cross-encoder, accessed via
  OpenRouter's rerank proxy endpoint.

  Sends the query and candidate documents to OpenRouter, which forwards
  to Cohere and returns a relevance score per candidate. Single HTTP
  call, no listwise LLM prompting, no JSON-parsing fragility.

  Authenticates with the `OPENROUTER_API_KEY` env var.

  On error, timeout, or malformed response returns `{:error, reason}` so
  the dispatcher in `Sanbase.Knowledge.Reranker` falls back to the input
  order and the user-facing query path never breaks.
  """

  @behaviour Sanbase.Knowledge.Reranker

  require Logger

  @base_url "https://openrouter.ai/api/v1/rerank"
  @model "cohere/rerank-v3.5"
  @default_timeout_ms 10_000
  @default_max_retries 2
  @max_candidate_chars 600

  @doc "Declares the candidate-text format style this backend wants."
  def style(), do: :cross_encoder

  @impl true
  def rerank(_query, [], _opts), do: {:ok, []}

  def rerank(query, candidates, opts) when is_binary(query) and is_list(candidates) do
    http_post = Keyword.get(opts, :http_post, &default_http_post/2)
    model = Keyword.get(opts, :model, @model)
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    max_retries = Keyword.get(opts, :max_retries, @default_max_retries)
    api_key = Keyword.get(opts, :api_key, openrouter_apikey())

    body = build_request_body(query, candidates, model)

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    req_opts = [
      json: body,
      headers: headers,
      receive_timeout: timeout_ms,
      retry: :transient,
      max_retries: max_retries
    ]

    started_at = System.monotonic_time(:millisecond)

    case http_post.(@base_url, req_opts) do
      {:ok, %{status: 200, body: response}} ->
        elapsed = System.monotonic_time(:millisecond) - started_at

        case parse_results(response) do
          {:ok, results} ->
            :telemetry.execute(
              [:sanbase, :knowledge, :rerank, :stop],
              %{duration_ms: elapsed, candidates: length(candidates)},
              %{model: model, source: opts[:source]}
            )

            {:ok, apply_results(candidates, results)}

          {:error, reason} = err ->
            Logger.warning("Reranker.OpenRouterCohere bad response: #{inspect(reason)}")
            err
        end

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Reranker.OpenRouterCohere HTTP #{status}: #{inspect(body)}")
        {:error, {:http_status, status}}

      {:error, reason} ->
        Logger.warning("Reranker.OpenRouterCohere transport error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Build the JSON body sent to OpenRouter's rerank endpoint.

  Mirrors Cohere's `/v2/rerank` request shape:
  `{model, query, documents, top_n}`. `top_n` is set to the candidate
  count so we receive a score for every candidate and can return the
  full reordered list to the dispatcher.

  Public so tests can assert on the body without an HTTP round-trip.
  """
  def build_request_body(query, candidates, model \\ @model) do
    documents = Enum.map(candidates, fn c -> truncate(c.text) end)

    %{
      "model" => model,
      "query" => query,
      "documents" => documents,
      "top_n" => length(candidates)
    }
  end

  @doc """
  Reorder `candidates` by the relevance scores returned by Cohere.

  `results` is a list of `%{"index" => i, "relevance_score" => s}` maps
  with 0-based indices into the original candidate list. Indices that
  are out of range, repeated, or missing are handled gracefully:
  missing candidates are appended in their original order at the tail.

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
  defp relevance_score(_), do: 0.0

  defp parse_results(%{"results" => results}) when is_list(results), do: {:ok, results}
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

  defp openrouter_apikey() do
    System.get_env("OPENROUTER_API_KEY")
  end
end
