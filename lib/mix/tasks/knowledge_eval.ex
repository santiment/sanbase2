defmodule Mix.Tasks.KnowledgeEval do
  @moduledoc """
  Run the knowledge retrieval eval harness against a golden question set.

  Reports hit@1/3/5/10, MRR, and mean top-1 cosine similarity per source.

  ## Usage

      mix knowledge_eval
      mix knowledge_eval --source faq
      mix knowledge_eval --source faq,academy
      mix knowledge_eval --file priv/knowledge/eval/custom.exs
      mix knowledge_eval --json /tmp/eval.json
      mix knowledge_eval --top-k 20 --limit 10 --verbose

  ## Options

    * `--source` - comma-separated subset of `faq,academy,insight`; defaults to all
    * `--file`   - path to a golden set; defaults to `priv/knowledge/eval/golden_set.exs`
    * `--json`   - dump full results (per-item + summary) as JSON to this path
    * `--top-k`  - top-K to retrieve per source (default 20)
    * `--prompt-top-n` - reranked hits per source that reach the prompt;
      context recall is measured over this window (default 5)
    * `--limit`  - cap the number of golden items evaluated
    * `--concurrency` - parallel items in flight (default 4)
    * `--no-rerank` - skip reranking (force the Noop reranker). Use to capture
      a coarse-retrieval baseline and compare against the reranked run.
    * `--verbose` / `-v` - print per-question rank breakdown
  """

  use Mix.Task

  @shortdoc "Evaluate FAQ/Academy/Insight retrieval vs a golden question set"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [
          source: :string,
          file: :string,
          json: :string,
          verbose: :boolean,
          top_k: :integer,
          prompt_top_n: :integer,
          limit: :integer,
          concurrency: :integer,
          no_rerank: :boolean
        ],
        aliases: [v: :verbose]
      )

    if invalid != [], do: Mix.raise("Invalid flags: #{inspect(invalid)}")
    if rest != [], do: Mix.raise("Unexpected arguments: #{inspect(rest)}")

    eval_opts = build_eval_opts(opts)
    %{items: results, summary: summary} = Sanbase.Knowledge.Eval.run(eval_opts)

    print_summary(summary, length(results))
    if opts[:verbose], do: print_per_item(results, eval_opts[:sources])
    if opts[:json], do: write_json(opts[:json], results, summary)

    :ok
  end

  defp build_eval_opts(opts) do
    sources = parse_sources(opts[:source])

    [sources: sources, progress: true]
    |> maybe_put(:file, opts[:file])
    |> maybe_put(:top_k, opts[:top_k])
    |> maybe_put(:prompt_top_n, opts[:prompt_top_n])
    |> maybe_put(:limit, opts[:limit])
    |> maybe_put(:concurrency, opts[:concurrency])
    |> maybe_put_reranker(opts[:no_rerank])
  end

  @allowed_sources ~w(faq academy insight)

  defp maybe_put_reranker(opts, true),
    do: Keyword.put(opts, :reranker, Sanbase.Knowledge.Reranker.Noop)

  defp maybe_put_reranker(opts, _), do: opts

  defp parse_sources(nil), do: [:faq, :academy, :insight]
  defp parse_sources("all"), do: [:faq, :academy, :insight]

  defp parse_sources(str) when is_binary(str) do
    str
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(fn
      src when src in @allowed_sources ->
        String.to_existing_atom(src)

      other ->
        Mix.raise(
          "Unsupported --source #{inspect(other)}. Allowed: #{Enum.join(@allowed_sources, ",")}"
        )
    end)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp print_summary(summary, total_items) do
    IO.puts("")
    IO.puts("=== Knowledge Eval Summary (#{total_items} item(s)) ===")

    {context, per_source} = Map.pop(summary, :context)

    Enum.each(per_source, fn {source, metrics} ->
      IO.puts("")
      IO.puts("[#{source}] evaluated=#{metrics.evaluated}")

      if metrics.evaluated > 0 do
        IO.puts("  hit@1   #{fmt(metrics.hit_at_1)}")
        IO.puts("  hit@3   #{fmt(metrics.hit_at_3)}")
        IO.puts("  hit@5   #{fmt(metrics.hit_at_5)}")
        IO.puts("  hit@10  #{fmt(metrics.hit_at_10)}")
        IO.puts("  MRR     #{fmt(metrics.mean_mrr)}")
        IO.puts("  mean top1 sim #{fmt(metrics.mean_top1_similarity)}")
      end
    end)

    print_context(context)

    IO.puts("")
  end

  defp print_context(nil), do: :ok

  defp print_context(%{evaluated: 0}) do
    IO.puts("")
    IO.puts("[context] no items with answer_facts — recall not measured")
  end

  defp print_context(%{evaluated: n} = ctx) do
    IO.puts("")
    IO.puts("[context] evaluated=#{n}")
    IO.puts("  mean recall #{fmt(ctx.mean_recall)}")
    IO.puts("  mean chars  #{round(ctx.mean_chars)}")
  end

  defp print_per_item(results, sources) do
    IO.puts("=== Per-question ===")

    Enum.each(results, fn r ->
      IO.puts("")
      IO.puts("#{r.id}: #{r.question}")

      if err = Map.get(r, :error) do
        IO.puts("  error=#{err}")
      end

      Enum.each(sources, fn src ->
        case Map.get(r, src) do
          nil ->
            :ok

          %{error: err} ->
            IO.puts("  [#{src}] error=#{err}")

          %{skipped: true, top1_similarity: sim} ->
            IO.puts("  [#{src}] (no expected) top1=#{fmt(sim)}")

          %{first_rank: rank, mrr: mrr, top1_similarity: sim} ->
            IO.puts("  [#{src}] rank=#{rank} mrr=#{fmt(mrr)} top1=#{fmt(sim)}")
        end
      end)

      print_item_context(Map.get(r, :context))
    end)

    IO.puts("")
  end

  defp print_item_context(%{recall: r, matched: m, total: t}) when is_number(r) do
    IO.puts("  [context] recall=#{fmt(r)} (#{m}/#{t})")
  end

  defp print_item_context(_), do: :ok

  defp write_json(path, results, summary) do
    File.mkdir_p!(Path.dirname(path))
    payload = %{items: results, summary: summary}
    File.write!(path, Jason.encode!(payload, pretty: true))
    IO.puts("JSON written to #{path}")
  end

  defp fmt(num) when is_number(num) do
    :erlang.float_to_binary(num / 1, decimals: 3)
  end

  defp fmt(_), do: "n/a"
end
