defmodule Sanbase.Knowledge.Indexer do
  @moduledoc """
  Single entry point for (re)building every knowledge embedding index — FAQ
  entries, Insight posts, and Academy articles.

  Each source is re-embedded by its owning module (`Faq.embed_all/0`,
  `PostEmbedding.embed_all_posts/0`, `Academy.reindex_academy/1`); this module
  just orchestrates them behind one uniform API. It runs them sequentially —
  to avoid hammering the embedding API and its rate limits — isolates failures
  so one source erroring does not abort the others, and reports per-source
  timing and outcome.

      Sanbase.Knowledge.Indexer.reindex_all()
      Sanbase.Knowledge.Indexer.reindex(:academy, branch: "production", force: true)
      Sanbase.Knowledge.Indexer.reindex([:faq, :insight])

  Returns a `%{source => result}` map; see `reindex/2`.
  """

  require Logger

  alias Sanbase.Knowledge.{Academy, Faq}
  alias Sanbase.Insight.PostEmbedding

  @sources [:faq, :insight, :academy]

  @type source :: :faq | :insight | :academy
  @type result :: %{status: :ok | :error, took_ms: non_neg_integer(), error: term() | nil}

  @doc "All sources this indexer knows how to (re)build."
  @spec sources() :: [source()]
  def sources(), do: @sources

  @doc """
  Re-embed every source. Equivalent to `reindex(sources(), opts)`.
  """
  @spec reindex_all(keyword()) :: %{source() => result()}
  def reindex_all(opts \\ []), do: reindex(@sources, opts)

  @doc """
  Re-embed one source or a list of sources.

  Options are forwarded to each per-source job; only Academy currently reads
  any (`:branch`, `:dry_run`, `:force`). Returns a map of `source => result`,
  where each result is `%{status: :ok | :error, took_ms: ms, error: reason}`.
  Sources run sequentially and an error in one does not stop the others.

  Raises `ArgumentError` if given a source that is not in `sources/0`.
  """
  @spec reindex(source() | [source()], keyword()) :: %{source() => result()}
  def reindex(source_or_sources, opts \\ [])

  def reindex(source, opts) when is_atom(source), do: reindex([source], opts)

  def reindex(sources, opts) when is_list(sources) do
    validate_sources!(sources)

    started = System.monotonic_time(:millisecond)
    Logger.info("[KnowledgeIndexer] reindex start sources=#{inspect(sources)}")

    results = Map.new(sources, fn source -> {source, run_source(source, opts)} end)

    took_ms = System.monotonic_time(:millisecond) - started
    Logger.info("[KnowledgeIndexer] reindex done took_ms=#{took_ms} #{summary(results)}")

    results
  end

  # Private functions

  defp validate_sources!(sources) do
    case Enum.reject(sources, &(&1 in @sources)) do
      [] ->
        :ok

      unknown ->
        raise ArgumentError,
              "unknown source(s): #{inspect(unknown)}. Known sources: #{inspect(@sources)}"
    end
  end

  # Runs one source's job, timing it and trapping any error into a uniform
  # result so a single failure never aborts the rest of the run.
  defp run_source(source, opts) do
    started = System.monotonic_time(:millisecond)
    Logger.info("[KnowledgeIndexer] #{source} start")

    outcome =
      try do
        do_reindex(source, opts)
      rescue
        e -> {:error, Exception.message(e)}
      catch
        kind, reason -> {:error, {kind, reason}}
      end

    took_ms = System.monotonic_time(:millisecond) - started

    case outcome do
      {:error, reason} ->
        Logger.error(
          "[KnowledgeIndexer] #{source} error took_ms=#{took_ms} reason=#{inspect(reason)}"
        )

        %{status: :error, took_ms: took_ms, error: reason}

      _ok ->
        Logger.info("[KnowledgeIndexer] #{source} ok took_ms=#{took_ms}")
        %{status: :ok, took_ms: took_ms, error: nil}
    end
  end

  # Adding a new source is a one-line entry above plus one clause here.
  defp do_reindex(:faq, _opts), do: Faq.embed_all()
  defp do_reindex(:insight, _opts), do: PostEmbedding.embed_all_posts()
  defp do_reindex(:academy, opts), do: Academy.reindex_academy(opts)

  defp summary(results) do
    Enum.map_join(results, " ", fn {source, %{status: status, took_ms: ms}} ->
      "#{source}=#{status}/#{ms}ms"
    end)
  end
end
