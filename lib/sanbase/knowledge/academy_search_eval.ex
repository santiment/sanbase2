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
      missing_heading_top5: Enum.count(top5, &is_nil(&1.heading)),
      bad_heading_top5: Enum.count(top5, &bad_heading?(&1.heading)),
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
      missing_heading_top5: mean(Enum.map(ok, & &1.missing_heading_top5)),
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

  # Answers ------------------------------------------------------------

  @judge_model "gpt-6-luna"
  @judge_reference_chars 6_000

  @doc "Default path of the bundled follow-up question set."
  @spec default_followup_set_path() :: String.t()
  def default_followup_set_path() do
    Application.app_dir(:sanbase, "priv/knowledge/eval/academy_followup_set.exs")
  end

  @doc """
  Eval of the Academy Q&A chat answers (`sendChatMessage` with `ACADEMY_QA`):
  runs `AcademyAIService.answer/2` for the golden questions plus the follow-up
  set (second turns of a chat) and scores what the user reads. Nothing is
  saved to a chat. Costs one answer LLM call per item (plus a rewrite call per
  follow-up and a judge call per answer).

      a = E.run_answers()
      E.print_answers(a)
      E.compare(a_before, a)

  Per item:
    * whether the answer is the "not in the Academy" message (`dk`)
    * `fact_recall` - share of the item's answer phrases found in the answer
    * `cited_expected` / `cited_relevant` - a cited source is the expected page,
      or an expected or acceptable page
    * `judge` - 1..5 from an LLM that sees the question, the answer and the
      expected page's content (`judge: false` skips it)

  Options:
    * `:file`, `:followup_file` - item sets (`followup_file: nil` skips follow-ups)
    * `:ids` - only these item ids
    * `:answer_opts` - passed to `AcademyAIService.answer/2`, e.g. `[model: "gpt-6-luna"]`
    * `:judge` - run the LLM judge (default true)
    * `:concurrency` - parallel items (default 4)
  """
  @spec run_answers(keyword()) :: map()
  def run_answers(opts \\ []) do
    judge? = Keyword.get(opts, :judge, true)
    answer_opts = Keyword.get(opts, :answer_opts, [])

    items =
      [
        Keyword.get(opts, :file, default_golden_set_path()),
        Keyword.get(opts, :followup_file, default_followup_set_path())
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.flat_map(&load_items/1)
      |> maybe_filter_ids(opts[:ids])

    results =
      items
      |> Task.async_stream(&evaluate_answer(&1, answer_opts, judge?),
        max_concurrency: Keyword.get(opts, :concurrency, 4),
        timeout: :infinity,
        ordered: true
      )
      |> Enum.map(fn {:ok, result} -> result end)

    %{
      ran_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      opts: %{answer_opts: inspect(answer_opts), judge: judge?},
      summary: summarize_answers(results),
      items: results
    }
  end

  @doc "Print an answer eval result: summary, then one line per item."
  @spec print_answers(map()) :: :ok
  def print_answers(%{summary: summary, items: items}) do
    IO.puts("== Academy answer eval ==")
    Enum.each(summary, fn {k, v} -> IO.puts("  #{k}: #{format(v)}") end)
    IO.puts("\n  id | dk | fact_recall | cited_expected | judge | search_query")

    Enum.each(items, fn i ->
      IO.puts(
        "  #{i.id} | #{i.dk} | #{format(i.fact_recall)} | #{i.cited_expected} | " <>
          "#{format(i.judge)} | #{i.search_query}"
      )
    end)
  end

  defp evaluate_answer(item, answer_opts, judge?) do
    opts =
      Keyword.merge(
        [
          chat_history: Map.get(item, :history, []),
          include_suggestions: false,
          tracing_environment: "eval"
        ],
        answer_opts
      )

    started = System.monotonic_time(:millisecond)
    result = AcademyAIService.answer(item.question, opts)
    latency = System.monotonic_time(:millisecond) - started

    case result do
      {:ok, %{answer: answer, sources: sources, search_query: search_query}} ->
        dk = answer == AcademyAIService.dont_know_message()
        urls = Enum.map(sources, & &1["url"])
        relevant = item.expected_urls ++ Map.get(item, :acceptable_urls, [])

        fact_recall =
          case Eval.context_recall(answer, item.answer_facts) do
            nil -> nil
            %{recall: recall} -> recall
          end

        %{
          id: item.id,
          type: item.type,
          negative: item.negative,
          followup: Map.has_key?(item, :history),
          dk: dk,
          fact_recall: if(dk, do: 0.0, else: fact_recall),
          cited_expected: Enum.any?(urls, &(&1 in item.expected_urls)),
          cited_relevant: Enum.any?(urls, &(&1 in relevant)),
          judge: if(judge? and not item.negative and not dk, do: judge(item, answer)),
          search_query: search_query,
          sources: urls,
          answer: String.slice(answer, 0, 600),
          latency_ms: latency,
          error: nil
        }

      {:error, reason} ->
        %{
          id: item.id,
          type: item.type,
          negative: item.negative,
          error: inspect(reason),
          latency_ms: latency
        }
    end
  end

  # 1..5: is the answer correct and complete for the question, judged against the
  # expected page. nil when the judge call fails.
  defp judge(item, answer) do
    reference =
      from(c in AcademyArticleChunk,
        join: a in AcademyArticle,
        on: a.id == c.article_id,
        where: a.academy_url in ^item.expected_urls and c.is_stale == false,
        order_by: [a.id, c.chunk_index],
        select: c.content
      )
      |> Repo.all()
      |> Enum.join("\n\n")
      |> String.slice(0, @judge_reference_chars)

    history =
      item
      |> Map.get(:history, [])
      |> Enum.map_join("\n", &"#{&1.role}: #{&1.content}")

    prompt = """
    You grade answers of a documentation assistant for the Santiment Academy.
    Score the answer from 1 to 5 against the reference documentation:
    5 = correct and answers the question fully; 4 = correct, minor omissions;
    3 = partly correct or vague; 2 = mostly misses the question; 1 = wrong or unsupported.
    Do not reward length. Reply with JSON only: {"score": <1-5>, "reason": "<one sentence>"}.

    #{if history != "", do: "Conversation before the question:\n#{history}\n", else: ""}
    Question: #{item.question}

    Key facts the answer should contain: #{Enum.join(item.answer_facts, "; ")}

    Reference documentation:
    #{reference}

    Answer to grade:
    #{answer}
    """

    with {:ok, content} <-
           Sanbase.OpenAI.Question.ask(prompt, %{
             model: @judge_model,
             reasoning_effort: "low",
             response_format: %{"type" => "json_object"},
             trace_name: "academy.eval.judge",
             environment: "eval"
           }),
         {:ok, %{"score" => score}} when is_integer(score) and score in 1..5 <-
           Jason.decode(content) do
      score
    else
      _ -> nil
    end
  end

  defp summarize_answers(results) do
    {errors, ok} = Enum.split_with(results, &(&1.error != nil))
    {negatives, answerable} = Enum.split_with(ok, & &1.negative)
    {followups, single} = Enum.split_with(answerable, & &1.followup)
    latencies = ok |> Enum.map(& &1.latency_ms) |> Enum.sort()
    judged = answerable |> Enum.map(& &1.judge) |> Enum.reject(&is_nil/1)

    %{
      items: length(results),
      errors: length(errors),
      answerable: length(answerable),
      answered_rate: rate(answerable, &(not &1.dk)),
      fact_recall: mean(answerable |> Enum.map(& &1.fact_recall) |> Enum.reject(&is_nil/1)),
      cited_expected: rate(answerable, & &1.cited_expected),
      cited_relevant: rate(answerable, & &1.cited_relevant),
      judge_mean: mean(judged),
      judge_good_rate: rate(judged, &(&1 >= 4)),
      followup_answered_rate: rate(followups, &(not &1.dk)),
      followup_cited_relevant: rate(followups, & &1.cited_relevant),
      single_cited_relevant: rate(single, & &1.cited_relevant),
      negative_dk_rate: rate(negatives, & &1.dk),
      latency_p50_ms: percentile(latencies, 0.5),
      latency_p95_ms: percentile(latencies, 0.95)
    }
  end

  # Autocomplete -------------------------------------------------------

  @doc "Default path of the bundled autocomplete prefix set."
  @spec default_autocomplete_set_path() :: String.t()
  def default_autocomplete_set_path() do
    Application.app_dir(:sanbase, "priv/knowledge/eval/academy_autocomplete_set.exs")
  end

  @doc """
  Eval of `academyAutocompleteQuestions` over the bundled prefix set: how
  often a prefix gets no suggestions, whether a suggestion points to the
  expected page, and latency. No API calls.

      r = E.run_autocomplete()
      E.print_autocomplete(r)

  Options:
    * `:file` - prefix set path (default: bundled `academy_autocomplete_set.exs`)
    * `:suggest_fun` - `fn prefix -> [%{url: _, question: _}] end`, to A/B another
      matcher (default `Sanbase.Knowledge.AcademyQuestions.suggest/1`)
  """
  @spec run_autocomplete(keyword()) :: map()
  def run_autocomplete(opts \\ []) do
    file = Keyword.get(opts, :file, default_autocomplete_set_path())
    suggest_fun = Keyword.get(opts, :suggest_fun, &Sanbase.Knowledge.AcademyQuestions.suggest/1)

    items =
      file
      |> load_items()
      |> Enum.map(fn item ->
        {micros, suggestions} = :timer.tc(fn -> suggest_fun.(item.prefix) end)
        urls = Enum.map(suggestions, & &1.url)
        rank = Enum.find_index(urls, &(&1 in item.expected_urls))

        %{
          prefix: item.prefix,
          type: item.type,
          negative: Map.get(item, :negative, false),
          count: length(suggestions),
          hit_rank: rank && rank + 1,
          latency_ms: micros / 1000,
          suggestions: Enum.map(suggestions, & &1.question)
        }
      end)

    %{
      summary: summarize_autocomplete(items),
      items: items,
      ran_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  @doc "Print an autocomplete eval result."
  @spec print_autocomplete(map()) :: :ok
  def print_autocomplete(%{summary: summary, items: items}) do
    Enum.each(summary, fn {key, value} -> IO.puts("#{key}: #{format(value)}") end)
    IO.puts("")

    Enum.each(items, fn item ->
      mark =
        cond do
          item.negative -> "neg"
          item.hit_rank -> "@#{item.hit_rank}"
          item.count == 0 -> "EMPTY"
          true -> "miss"
        end

      IO.puts(
        "#{String.pad_trailing(mark, 6)}#{item.prefix} -> #{List.first(item.suggestions) || ""}"
      )
    end)
  end

  defp summarize_autocomplete(items) do
    {negatives, answerable} = Enum.split_with(items, & &1.negative)
    latencies = items |> Enum.map(& &1.latency_ms) |> Enum.sort()

    by_type =
      answerable
      |> Enum.group_by(& &1.type)
      |> Map.new(fn {type, list} -> {type, rate(list, & &1.hit_rank)} end)

    %{
      prefixes: length(answerable),
      empty_rate: rate(answerable, &(&1.count == 0)),
      hit_at_1: rate(answerable, &(&1.hit_rank == 1)),
      hit_at_5: rate(answerable, &(&1.hit_rank && &1.hit_rank <= 5)),
      hit_at_5_by_type: by_type,
      mean_suggestions: mean(Enum.map(answerable, & &1.count)),
      negative_nonempty_rate: rate(negatives, &(&1.count > 0)),
      latency_p50_ms: percentile(latencies, 0.5),
      latency_p95_ms: percentile(latencies, 0.95)
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
  defp format(v) when is_map(v), do: Enum.map_join(v, " ", fn {k, x} -> "#{k}=#{format(x)}" end)
  defp format(nil), do: "-"
  defp format(v), do: to_string(v)

  defp load_items(path) do
    {data, _bindings} = Code.eval_file(path)
    Map.fetch!(data, :items)
  end

  defp maybe_filter_ids(items, nil), do: items
  defp maybe_filter_ids(items, ids), do: Enum.filter(items, &(&1.id in ids))
end
