defmodule Sanbase.Knowledge.Eval do
  @moduledoc """
  Offline evaluation harness for FAQ / Academy / Insight retrieval.

  Reads a golden question set, runs the same retrieval functions the live
  pipeline uses, and reports hit@K, MRR, and mean top-1 cosine similarity
  per source. The metrics are meant to be diffed across runs to gate
  changes to the embedding model, threshold, chunking, or retrieval logic.

  Designed to be called from `mix knowledge.eval` but also usable directly
  from IEx.
  """

  alias Sanbase.Knowledge.{Academy, Faq}
  alias Sanbase.Insight.Post

  @default_top_k 10
  @all_sources [:faq, :academy, :insights]

  @type item :: %{
          required(:id) => String.t(),
          required(:question) => String.t(),
          optional(:expected) => %{
            optional(:faq_ids) => [String.t()],
            optional(:academy_paths) => [String.t()],
            optional(:insight_post_ids) => [integer()]
          },
          optional(:tags) => [String.t()]
        }

  @type opts :: [
          file: String.t() | nil,
          sources: [atom()],
          top_k: pos_integer(),
          limit: pos_integer() | nil
        ]

  @doc """
  Run the eval and return `%{items: per_item_results, summary: aggregate}`.
  """
  @spec run(opts()) :: %{items: [map()], summary: map()}
  def run(opts \\ []) do
    items =
      opts
      |> Keyword.get(:file)
      |> load_items()
      |> maybe_limit(opts[:limit])

    top_k = Keyword.get(opts, :top_k, @default_top_k)
    sources = Keyword.get(opts, :sources, @all_sources)

    results = Enum.map(items, &evaluate_item(&1, top_k, sources))
    summary = summarize(results, sources)

    %{items: results, summary: summary}
  end

  @doc """
  Default path of the bundled golden set.
  """
  @spec default_golden_set_path() :: String.t()
  def default_golden_set_path() do
    Application.app_dir(:sanbase, "priv/knowledge/eval/golden_set.exs")
  end

  @doc """
  Score one source's hits against expected ids.

  Public so it can be unit-tested without touching the DB or the embedding API.
  """
  @spec score_hits([map()], [term()], (map() -> term())) :: map()
  def score_hits(hits, expected, id_fn) when is_list(hits) and is_list(expected) do
    base = %{
      retrieved: length(hits),
      expected_count: length(expected),
      top1_similarity: top1_similarity(hits)
    }

    if expected == [] do
      Map.put(base, :skipped, true)
    else
      ranks =
        hits
        |> Enum.with_index(1)
        |> Enum.filter(fn {hit, _rank} -> id_fn.(hit) in expected end)
        |> Enum.map(fn {_hit, rank} -> rank end)

      first_rank = List.first(ranks) || 0

      Map.merge(base, %{
        first_rank: first_rank,
        mrr: if(first_rank > 0, do: 1 / first_rank, else: 0.0),
        hit_at_1: first_rank == 1,
        hit_at_3: first_rank > 0 and first_rank <= 3,
        hit_at_5: first_rank > 0 and first_rank <= 5,
        hit_at_10: first_rank > 0 and first_rank <= 10
      })
    end
  end

  @doc """
  Aggregate per-item scores into mean metrics per source.

  Public for testing.
  """
  @spec summarize([map()], [atom()]) :: map()
  def summarize(results, sources \\ @all_sources) do
    Enum.reduce(sources, %{}, fn src, acc ->
      Map.put(acc, src, summarize_source(results, src))
    end)
  end

  # Private functions

  defp evaluate_item(item, top_k, sources) do
    {:ok, [embedding]} = Sanbase.AI.Embedding.generate_embeddings([item.question], 1536)

    per_source =
      sources
      |> Enum.map(fn src -> {src, eval_source(src, item, embedding, top_k)} end)
      |> Map.new()

    Map.merge(%{id: item.id, question: item.question, tags: Map.get(item, :tags, [])}, per_source)
  end

  defp eval_source(:faq, item, embedding, top_k) do
    {:ok, hits} = Faq.find_most_similar_faqs(embedding, top_k)
    expected = get_in(item, [:expected, :faq_ids]) || []
    score_hits(hits, expected, & &1.id)
  end

  defp eval_source(:academy, item, embedding, top_k) do
    {:ok, hits} = Academy.search_chunks(embedding, top_k)
    expected = get_in(item, [:expected, :academy_paths]) || []
    score_hits(hits, expected, & &1.github_path)
  end

  defp eval_source(:insights, item, embedding, top_k) do
    {:ok, hits} = Post.find_most_similar_insight_chunks(embedding, top_k)
    hits = Enum.uniq_by(hits, & &1.post_id)
    expected = get_in(item, [:expected, :insight_post_ids]) || []
    score_hits(hits, expected, & &1.post_id)
  end

  defp summarize_source(results, src) do
    scored =
      results
      |> Enum.map(&Map.get(&1, src))
      |> Enum.reject(&skipped_or_nil?/1)

    evaluated = length(scored)

    if evaluated == 0 do
      %{evaluated: 0}
    else
      %{
        evaluated: evaluated,
        mean_mrr: average(scored, & &1.mrr),
        hit_at_1: average(scored, &bool_num(&1.hit_at_1)),
        hit_at_3: average(scored, &bool_num(&1.hit_at_3)),
        hit_at_5: average(scored, &bool_num(&1.hit_at_5)),
        hit_at_10: average(scored, &bool_num(&1.hit_at_10)),
        mean_top1_similarity: average(scored, &(&1.top1_similarity || 0.0))
      }
    end
  end

  defp skipped_or_nil?(nil), do: true
  defp skipped_or_nil?(%{skipped: true}), do: true
  defp skipped_or_nil?(_), do: false

  defp average(list, fun) do
    list
    |> Enum.map(fun)
    |> Enum.sum()
    |> Kernel./(length(list))
  end

  defp bool_num(true), do: 1.0
  defp bool_num(_), do: 0.0

  defp top1_similarity([]), do: nil
  defp top1_similarity([%{similarity: sim} | _]), do: sim
  defp top1_similarity([_ | _]), do: nil

  defp maybe_limit(items, nil), do: items
  defp maybe_limit(items, n) when is_integer(n) and n > 0, do: Enum.take(items, n)

  defp load_items(nil), do: load_items(default_golden_set_path())

  defp load_items(path) when is_binary(path) do
    {data, _bindings} = Code.eval_file(path)

    case data do
      %{items: items} when is_list(items) -> items
      items when is_list(items) -> items
      _ -> raise "Golden set at #{path} must return %{items: [...]} or a list of items"
    end
  end
end
