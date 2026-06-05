defmodule Sanbase.Knowledge.Eval do
  @moduledoc """
  Offline evaluation harness for FAQ / Academy / Insight retrieval.

  Reads a golden question set, runs the same retrieval functions the live
  pipeline uses, and reports hit@K, MRR, and mean top-1 cosine similarity
  per source. The metrics are meant to be diffed across runs to gate
  changes to the embedding model, threshold, chunking, or retrieval logic.

  Designed to be called from `mix knowledge_eval` but also usable directly
  from IEx.
  """

  alias Sanbase.Knowledge.{Academy, Context, Faq}
  alias Sanbase.Insight.Post

  @default_top_k 20
  @default_concurrency 4
  @all_sources [:faq, :academy, :insight]

  @type item :: %{
          required(:id) => String.t(),
          required(:question) => String.t(),
          optional(:expected) => %{
            optional(:faq_ids) => [String.t()],
            optional(:academy_paths) => [String.t()],
            optional(:insight_post_ids) => [integer()]
          },
          # Short verbatim-ish phrases the answer depends on. Used to measure
          # context recall: the fraction present in the assembled prompt
          # context. Items without `answer_facts` skip recall scoring.
          optional(:answer_facts) => [String.t()],
          optional(:tags) => [String.t()]
        }

  @type opts :: [
          file: String.t() | nil,
          sources: [atom()],
          top_k: pos_integer(),
          prompt_top_n: pos_integer(),
          limit: pos_integer() | nil,
          random: boolean(),
          seed: integer() | nil,
          concurrency: pos_integer(),
          reranker: module() | nil,
          plan: false | :heuristic,
          progress: boolean()
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
      |> maybe_shuffle(opts[:random], opts[:seed])
      |> maybe_limit(opts[:limit])

    top_k = Keyword.get(opts, :top_k, @default_top_k)
    # Measure context over the same prompt window the live answer path uses.
    prompt_top_n = Keyword.get(opts, :prompt_top_n, Sanbase.Knowledge.prompt_top_n())
    sources = Keyword.get(opts, :sources, @all_sources)
    reranker = Keyword.get(opts, :reranker)
    plan_mode = Keyword.get(opts, :plan, false)
    concurrency = Keyword.get(opts, :concurrency, @default_concurrency)

    if not (is_integer(concurrency) and concurrency > 0) do
      raise ArgumentError,
            "concurrency must be a positive integer, got: #{inspect(concurrency)}"
    end

    progress = progress_tracker(opts[:progress], length(items))

    results =
      items
      |> Task.async_stream(
        fn item ->
          result = evaluate_item(item, top_k, prompt_top_n, sources, reranker, plan_mode)
          tick_progress(progress, item)
          result
        end,
        max_concurrency: concurrency,
        timeout: :infinity,
        ordered: true
      )
      |> Enum.map(fn {:ok, result} -> result end)

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
  Fraction of `facts` present in `context_text`.

  Both sides are normalized (downcased, punctuation stripped, whitespace
  collapsed) before a substring check, so facts should be short phrases
  copied near-verbatim from the source. Returns `nil` when there are no
  facts, so the item is skipped in recall aggregation.

  Public so it can be unit-tested without the DB or embedding API.
  """
  @spec context_recall(String.t(), [String.t()]) ::
          %{recall: float(), matched: non_neg_integer(), total: pos_integer()} | nil
  def context_recall(_context_text, []), do: nil

  def context_recall(context_text, facts) when is_binary(context_text) and is_list(facts) do
    normalized = normalize(context_text)
    matched = Enum.count(facts, fn fact -> String.contains?(normalized, normalize(fact)) end)
    total = length(facts)

    %{recall: matched / total, matched: matched, total: total}
  end

  @doc """
  Aggregate per-item scores into mean metrics per source.

  Adds a `:context` section with mean context recall and mean context size
  across items that carry `answer_facts`.

  Public for testing.
  """
  @spec summarize([map()], [atom()]) :: map()
  def summarize(results, sources \\ @all_sources) do
    sources
    |> Enum.reduce(%{}, fn src, acc ->
      Map.put(acc, src, summarize_source(results, src))
    end)
    |> Map.put(:context, summarize_context(results))
  end

  # Private functions

  defp evaluate_item(item, top_k, prompt_top_n, sources, reranker, plan_mode) do
    base = %{id: item.id, question: item.question, tags: Map.get(item, :tags, [])}

    case Sanbase.AI.Embedding.generate_embeddings([embed_query(item.question, plan_mode)], 1536) do
      {:ok, [embedding]} ->
        # Each source returns {score_map, ranked_hits}: the score map feeds
        # the per-source hit@K/MRR metrics, the ranked hits (already reranked,
        # same order that's scored) feed context assembly.
        per_source =
          Enum.map(sources, fn src ->
            {src, eval_source(src, item, embedding, top_k, reranker)}
          end)

        scores =
          per_source
          |> Enum.map(fn {src, {score, _hits}} -> {src, score} end)
          |> Map.new()

        context = assemble_item_context(per_source, prompt_top_n)

        base
        |> Map.merge(scores)
        |> Map.put(:context, score_context(context, Map.get(item, :answer_facts, [])))

      {:error, reason} ->
        Map.put(base, :error, inspect(reason))
    end
  end

  defp eval_source(:faq, item, embedding, top_k, reranker) do
    case Faq.find_most_similar_faqs(embedding, top_k) do
      {:ok, hits} ->
        hits = apply_reranker(hits, item.question, :faq, reranker, top_k)
        expected = get_in(item, [:expected, :faq_ids]) || []
        {score_hits(hits, expected, & &1.id), hits}

      {:error, reason} ->
        {%{error: inspect(reason), top1_similarity: nil}, []}
    end
  end

  defp eval_source(:academy, item, embedding, top_k, reranker) do
    case Academy.search_chunks(embedding, top_k) do
      {:ok, hits} ->
        hits = apply_reranker(hits, item.question, :academy, reranker, top_k)
        expected = get_in(item, [:expected, :academy_paths]) || []
        {score_hits(hits, expected, & &1.github_path), hits}

      {:error, reason} ->
        {%{error: inspect(reason), top1_similarity: nil}, []}
    end
  end

  defp eval_source(:insight, item, embedding, top_k, reranker) do
    case Post.find_most_similar_insight_chunks(embedding, top_k) do
      {:ok, hits} ->
        hits = Enum.uniq_by(hits, & &1.post_id)
        hits = apply_reranker(hits, item.question, :insight, reranker, top_k)
        expected = get_in(item, [:expected, :insight_post_ids]) || []
        {score_hits(hits, expected, & &1.post_id), hits}

      {:error, reason} ->
        {%{error: inspect(reason), top1_similarity: nil}, []}
    end
  end

  # `:heuristic` routes the embedded query through the same QueryPlan rewrite
  # the live path uses (deterministic — no LLM call), so the eval measures
  # retrieval over the rewritten query. Reranking still sees the raw question,
  # matching the live answer path. Recency *ordering* is deliberately not
  # applied to scoring: golden ids are topical, and a newest-first reorder
  # would make hit@K meaningless.
  defp embed_query(question, :heuristic) do
    Sanbase.Knowledge.QueryPlan.build(question, query_understanding: false).semantic_query
  end

  defp embed_query(question, _plan_mode), do: question

  # Assemble the prompt-window context across all sources for one item, using
  # the same Context builder the live prompt uses. Only the top prompt_top_n
  # reranked hits per source reach the prompt, so recall is measured on those.
  defp assemble_item_context(per_source, prompt_top_n) do
    per_source
    |> Enum.map(fn {src, {_score, hits}} ->
      hits
      |> Enum.take(prompt_top_n)
      |> Context.assemble(src)
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  # Reranks `hits` against `question` via the same seam the live answer path
  # uses. Passes `top_n: top_k` (no truncation) so scoring can still measure
  # hit@10 in the reordered list.
  defp apply_reranker(hits, question, source, reranker, top_k) do
    opts = [top_n: top_k] |> maybe_put(:reranker, reranker)
    Sanbase.Knowledge.rerank_entries(question, hits, source, opts)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp progress_tracker(true, total) when total > 0, do: {:atomics.new(1, []), total}
  defp progress_tracker(_, _), do: nil

  defp tick_progress(nil, _item), do: :ok

  defp tick_progress({counter, total}, item) do
    n = :atomics.add_get(counter, 1, 1)
    IO.puts("[#{n}/#{total}] #{item.id}")
  end

  defp score_context(context_text, facts) do
    recall = context_recall(context_text, facts) || %{recall: nil}
    Map.merge(%{text_chars: String.length(context_text)}, recall)
  end

  defp normalize(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}\s]/u, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp summarize_context(results) do
    scored = for %{context: %{recall: r} = ctx} <- results, is_number(r), do: ctx

    evaluated = length(scored)

    if evaluated == 0 do
      %{evaluated: 0}
    else
      %{
        evaluated: evaluated,
        mean_recall: average(scored, & &1.recall),
        mean_chars: average(scored, & &1.text_chars)
      }
    end
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
  defp skipped_or_nil?(%{error: _}), do: true
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

  defp maybe_limit(_items, n) do
    raise ArgumentError, "limit must be a positive integer, got: #{inspect(n)}"
  end

  defp maybe_shuffle(items, true, seed) when is_integer(seed) do
    :rand.seed(:exsss, seed)
    Enum.shuffle(items)
  end

  defp maybe_shuffle(items, true, _seed), do: Enum.shuffle(items)
  defp maybe_shuffle(items, _random, _seed), do: items

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
