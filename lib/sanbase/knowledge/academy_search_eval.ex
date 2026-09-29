defmodule Sanbase.Knowledge.AcademySearchEval do
  @moduledoc """
  Evaluation of the production Academy search path
  (`Sanbase.AI.AcademyAIService.semantic_search/2`, i.e. `academySearch`).

  Unlike `Sanbase.Knowledge.Eval`, which scores raw vector retrieval per
  chunk, this runs the exact function the GraphQL query uses (vector search,
  rerank, per-article cap) and scores it at page level, plus the properties of
  the returned chunks: noise, headings, stability across identical calls and
  latency. It calls the function directly, so it needs no HTTP access and is
  not subject to the public rate limit.

  Meant to be run from a remote shell (mix is not available on stage/prod):

      alias Sanbase.Knowledge.AcademySearchEval, as: E

      before = E.run()                  # 32 golden questions, 2 runs each
      E.print(before)
      E.save(before, "/tmp/academy_eval_before.json")

      # ... deploy / reindex ...

      after_ = E.run()
      E.compare(before, after_)
      E.index_stats()                   # quality of the stored chunks, no API calls

  Options for `run/1`:
    * `:file` - golden set path (default: bundled `academy_search_set.exs`)
    * `:runs` - identical calls per question, used for stability (default 2)
    * `:top_k` - results requested per call (default 10)
    * `:ids` - only evaluate these item ids
    * `:search_opts` - extra options passed to `semantic_search/2`, e.g.
      `[max_chunks_per_article: nil]` or `[reranker: Sanbase.Knowledge.Reranker.Noop]`
      to A/B a retrieval change on the live index
    * `:concurrency` - parallel questions (default 2)
  """

  import Ecto.Query

  alias Sanbase.AI.AcademyAIService
  alias Sanbase.Knowledge.{AcademyArticle, AcademyArticleChunk, AcademyMarkdown, Eval}
  alias Sanbase.Repo

  @default_runs 2
  @default_top_k 10
  @default_concurrency 2
  @stub_chars 200

  @doc "Default path of the bundled golden set."
  @spec default_golden_set_path() :: String.t()
  def default_golden_set_path() do
    Application.app_dir(:sanbase, "priv/knowledge/eval/academy_search_set.exs")
  end

  @doc "Run the eval. Returns `%{summary: map, items: [map], opts: map, ran_at: iso8601}`."
  @spec run(keyword()) :: map()
  def run(opts \\ []) do
    runs = Keyword.get(opts, :runs, @default_runs)
    top_k = Keyword.get(opts, :top_k, @default_top_k)
    search_opts = Keyword.get(opts, :search_opts, [])
    concurrency = Keyword.get(opts, :concurrency, @default_concurrency)

    items =
      opts
      |> Keyword.get(:file, default_golden_set_path())
      |> load_items()
      |> maybe_filter_ids(opts[:ids])

    results =
      items
      |> Task.async_stream(&evaluate_item(&1, runs, top_k, search_opts),
        max_concurrency: concurrency,
        timeout: :infinity,
        ordered: true
      )
      |> Enum.map(fn {:ok, result} -> result end)

    %{
      ran_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      opts: %{runs: runs, top_k: top_k, search_opts: inspect(search_opts)},
      summary: summarize(results),
      items: results
    }
  end

  @doc """
  Quality of the stored (non-stale) chunks, independent of any query: chunk
  counts, stub chunks, leftover markup, missing or malformed headings.
  """
  @spec index_stats() :: map()
  def index_stats() do
    chunks =
      from(c in AcademyArticleChunk,
        join: a in AcademyArticle,
        on: a.id == c.article_id,
        where: c.is_stale == false and a.is_stale == false,
        select: %{content: c.content, heading: c.heading, article_id: c.article_id}
      )
      |> Repo.all()

    total = length(chunks)

    %{
      articles: chunks |> Enum.uniq_by(& &1.article_id) |> length(),
      chunks: total,
      stub_chunks: Enum.count(chunks, &(String.length(&1.content) < @stub_chars)),
      markup_chunks: Enum.count(chunks, &AcademyMarkdown.markup_residue?(&1.content)),
      nil_heading_chunks: Enum.count(chunks, &is_nil(&1.heading)),
      bad_heading_chunks: Enum.count(chunks, &bad_heading?(&1.heading)),
      avg_chunk_chars:
        if(total > 0, do: div(Enum.sum_by(chunks, &String.length(&1.content)), total))
    }
  end

  @doc "Print a summary (and optionally per-item lines) to stdout."
  @spec print(map(), keyword()) :: :ok
  def print(%{summary: summary, items: items}, opts \\ []) do
    IO.puts("== Academy search eval ==")
    Enum.each(summary, fn {k, v} -> IO.puts("  #{k}: #{format(v)}") end)

    if Keyword.get(opts, :items, true) do
      IO.puts("\n  id | primary_rank | fact_recall | top1_sim | stability | latency_ms")

      Enum.each(items, fn i ->
        IO.puts(
          "  #{i.id} | #{i.primary_rank || "-"} | #{format(i.fact_recall)} | " <>
            "#{format(i.top1_similarity)} | #{format(i.stability)} | #{format(i.latency_ms)}"
        )
      end)
    end

    :ok
  end

  @doc "Print summary metrics of two runs side by side with the delta."
  @spec compare(map(), map()) :: :ok
  def compare(%{summary: a}, %{summary: b}) do
    IO.puts("metric | before | after | delta")

    a
    |> Map.keys()
    |> Enum.sort()
    |> Enum.each(fn key ->
      before = Map.get(a, key)
      after_ = Map.get(b, key)
      delta = if is_number(before) and is_number(after_), do: format(after_ - before), else: ""
      IO.puts("#{key} | #{format(before)} | #{format(after_)} | #{delta}")
    end)
  end

  @doc "Write a run to a JSON file."
  @spec save(map(), String.t()) :: :ok
  def save(result, path), do: File.write!(path, Jason.encode!(result, pretty: true))

  @doc "Read a run written by `save/2` (keys become atoms again for `compare/2`)."
  @spec load(String.t()) :: map()
  def load(path), do: path |> File.read!() |> Jason.decode!(keys: :atoms!)

  # Per item ---------------------------------------------------------------

  defp evaluate_item(item, runs, top_k, search_opts) do
    calls =
      for _ <- 1..runs do
        started = System.monotonic_time(:millisecond)
        result = AcademyAIService.semantic_search(item.question, [top_k: top_k] ++ search_opts)
        {result, System.monotonic_time(:millisecond) - started}
      end

    case calls do
      [{{:ok, hits}, _} | _] ->
        latencies = Enum.map(calls, &elem(&1, 1))
        other_runs = for {{:ok, h}, _} <- tl(calls), do: h
        score_item(item, hits, other_runs, latencies)

      [{{:error, reason}, _} | _] ->
        %{id: item.id, negative: item.negative, error: inspect(reason)}
    end
  end

  defp score_item(item, hits, other_runs, latencies) do
    top5 = Enum.take(hits, 5)
    page_ranks = hits |> Enum.map(& &1.url) |> Enum.uniq()
    primary_rank = first_rank(page_ranks, item.expected_urls)
    relevant = item.expected_urls ++ Map.get(item, :acceptable_urls, [])
    relevant_rank = first_rank(page_ranks, relevant)

    fact_recall =
      case Eval.context_recall(Enum.map_join(top5, "\n", & &1.chunk), item.answer_facts) do
        nil -> nil
        %{recall: recall} -> recall
      end

    %{
      id: item.id,
      type: item.type,
      negative: item.negative,
      primary_rank: primary_rank,
      hit_at_1: primary_rank == 1,
      hit_at_5: primary_rank != nil and primary_rank <= 5,
      reciprocal_rank: if(primary_rank, do: 1 / primary_rank, else: 0.0),
      # Rank of the first page that is either primary or acceptable. Less strict
      # than primary_rank when several pages answer the question.
      relevant_rank: relevant_rank,
      fact_recall: fact_recall,
      relevant_in_top5: Enum.count(top5, &(&1.url in relevant)),
      distinct_pages_top5: top5 |> Enum.uniq_by(& &1.url) |> length(),
      markup_top5: Enum.count(top5, &AcademyMarkdown.markup_residue?(&1.chunk)),
      stubs_top5: Enum.count(top5, &(String.length(&1.chunk) < @stub_chars)),
      bad_heading_top5: Enum.count(top5, &(is_nil(&1.heading) or bad_heading?(&1.heading))),
      top1_similarity: top1_similarity(hits),
      max_similarity: hits |> Enum.map(& &1.similarity) |> Enum.max(fn -> nil end),
      stability: stability(top5, other_runs),
      latency_ms: latencies,
      top: Enum.map(hits, &%{url: &1.url, heading: &1.heading, similarity: &1.similarity})
    }
  end

  defp first_rank(page_ranks, expected) do
    case Enum.find_index(page_ranks, &(&1 in expected)) do
      nil -> nil
      index -> index + 1
    end
  end

  # Mean Jaccard overlap of the top-5 chunk sets between the first call and
  # each repeat. 1.0 means identical sets on every call.
  defp stability(_top5, []), do: nil

  defp stability(top5, other_runs) do
    keys = MapSet.new(top5, &chunk_key/1)

    other_runs
    |> Enum.map(fn hits ->
      other = hits |> Enum.take(5) |> MapSet.new(&chunk_key/1)
      union = MapSet.union(keys, other) |> MapSet.size()
      if union == 0, do: 1.0, else: MapSet.size(MapSet.intersection(keys, other)) / union
    end)
    |> mean()
  end

  defp chunk_key(hit), do: {hit.article_id, hit.chunk_index}

  defp top1_similarity([%{similarity: sim} | _]), do: sim
  defp top1_similarity(_), do: nil

  defp bad_heading?(nil), do: false
  defp bad_heading?(heading), do: heading == "" or String.contains?(heading, ["](", "REF "])

  # Summary ----------------------------------------------------------------

  defp summarize(results) do
    ok = Enum.reject(results, &Map.has_key?(&1, :error))
    answerable = Enum.reject(ok, & &1.negative)
    negatives = Enum.filter(ok, & &1.negative)
    latencies = ok |> Enum.flat_map(& &1.latency_ms) |> Enum.sort()
    rank1_sims = for %{top1_similarity: s} <- answerable, is_number(s), do: s

    %{
      questions: length(results),
      errors: length(results) - length(ok),
      answerable: length(answerable),
      hit_at_1: rate(answerable, & &1.hit_at_1),
      hit_at_5: rate(answerable, & &1.hit_at_5),
      mrr: mean(Enum.map(answerable, & &1.reciprocal_rank)),
      relevant_at_1: rate(answerable, &(&1.relevant_rank == 1)),
      relevant_at_3: rate(answerable, &(&1.relevant_rank != nil and &1.relevant_rank <= 3)),
      fact_recall_top5: mean(for %{fact_recall: r} <- answerable, is_number(r), do: r),
      relevant_in_top5: mean(Enum.map(answerable, & &1.relevant_in_top5)),
      distinct_pages_top5: mean(Enum.map(ok, & &1.distinct_pages_top5)),
      markup_chunks_top5: mean(Enum.map(ok, & &1.markup_top5)),
      stub_chunks_top5: mean(Enum.map(ok, & &1.stubs_top5)),
      bad_heading_top5: mean(Enum.map(ok, & &1.bad_heading_top5)),
      stability_top5: mean(for %{stability: s} <- ok, is_number(s), do: s),
      answerable_min_top1_similarity: Enum.min(rank1_sims, fn -> nil end),
      negative_max_similarity:
        negatives
        |> Enum.map(& &1.max_similarity)
        |> Enum.reject(&is_nil/1)
        |> Enum.max(fn -> nil end),
      latency_p50_ms: percentile(latencies, 0.5),
      latency_p95_ms: percentile(latencies, 0.95),
      latency_max_ms: List.last(latencies)
    }
  end

  defp rate([], _fun), do: nil
  defp rate(list, fun), do: Enum.count(list, fun) / length(list)

  defp mean([]), do: nil
  defp mean(list), do: Enum.sum(list) / length(list)

  defp percentile([], _p), do: nil

  defp percentile(sorted, p),
    do: Enum.at(sorted, min(length(sorted) - 1, trunc(p * length(sorted))))

  defp format(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 3)
  defp format(v) when is_list(v), do: Enum.map_join(v, ",", &format/1)
  defp format(nil), do: "-"
  defp format(v), do: to_string(v)

  defp load_items(path) do
    {data, _bindings} = Code.eval_file(path)
    Map.fetch!(data, :items)
  end

  defp maybe_filter_ids(items, nil), do: items
  defp maybe_filter_ids(items, ids), do: Enum.filter(items, &(&1.id in ids))
end
