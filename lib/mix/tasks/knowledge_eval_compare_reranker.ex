defmodule Mix.Tasks.KnowledgeEvalCompareReranker do
  @moduledoc """
  Run the knowledge retrieval eval harness twice — baseline with the
  Noop reranker (pure cosine order) and treatment with the configured
  reranker — and print a side-by-side metric diff per source.

  Useful for measuring whether the reranker actually helps before
  shipping a config change. Hits the reranker backend (OpenAI by
  default) once per item per source on the treatment run, so subset
  with `--limit` when iterating.

  Embeddings are recomputed for both runs (one batch each), since the
  underlying `Sanbase.Knowledge.Eval.run/1` is invoked twice. That's
  the same coarse retrieval each time, so any score change is
  attributable to reranking.

  ## Usage

      mix knowledge_eval_compare_reranker
      mix knowledge_eval_compare_reranker --limit 10
      mix knowledge_eval_compare_reranker --source faq --limit 20 --verbose
      mix knowledge_eval_compare_reranker --treatment Sanbase.Knowledge.Reranker.OpenAI --top-k 10
      mix knowledge_eval_compare_reranker --json /tmp/compare.json

  ## Options

    * `--source`    - comma-separated subset of `faq,academy,insights`; defaults to all
    * `--file`      - path to a golden set; defaults to the bundled `priv/knowledge/eval/golden_set.exs`
    * `--limit`     - cap the number of golden items evaluated (recommended for compare runs)
    * `--random`    - shuffle items before applying `--limit` so the sample isn't always the first N
    * `--seed N`    - fix the shuffle seed (implies `--random`); reproduces a previous random run
    * `--concurrency N` - parallel items in flight per run (default 4)
    * `--top-k`     - top-K to retrieve per source before reranking (default 20)
    * `--treatment` - module to use as the treatment reranker; defaults to the configured default
    * `--baseline`  - module to use as the baseline reranker; defaults to `Sanbase.Knowledge.Reranker.Noop`
    * `--json`      - dump baseline + treatment + delta as JSON to this path
    * `--verbose` / `-v` - per-question rank delta
  """

  use Mix.Task

  alias Sanbase.Knowledge.Eval
  alias Sanbase.Knowledge.Reranker

  @shortdoc "Compare retrieval metrics with vs without reranker"

  @allowed_sources ~w(faq academy insights)
  @metric_rows [
    {:hit_at_1, "hit@1"},
    {:hit_at_3, "hit@3"},
    {:hit_at_5, "hit@5"},
    {:hit_at_10, "hit@10"},
    {:mean_mrr, "MRR"},
    {:mean_top1_similarity, "mean top1 sim"}
  ]

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
          limit: :integer,
          random: :boolean,
          seed: :integer,
          concurrency: :integer,
          treatment: :string,
          baseline: :string
        ],
        aliases: [v: :verbose]
      )

    if invalid != [], do: Mix.raise("Invalid flags: #{inspect(invalid)}")
    if rest != [], do: Mix.raise("Unexpected arguments: #{inspect(rest)}")

    base_opts = build_base_opts(opts)
    sources = base_opts[:sources]

    baseline_mod = resolve_module(opts[:baseline], Sanbase.Knowledge.Reranker.Noop)
    treatment_mod = resolve_module(opts[:treatment], default_reranker())

    if baseline_mod == treatment_mod do
      Mix.raise(
        "Baseline and treatment rerankers are the same module (#{inspect(baseline_mod)}) — nothing to compare. Override --treatment or change the configured default."
      )
    end

    if base_opts[:random], do: IO.puts("Random sample (seed=#{base_opts[:seed]})")

    IO.puts("Running baseline (#{inspect(baseline_mod)})…")
    baseline = Eval.run(Keyword.put(base_opts, :reranker, baseline_mod))

    IO.puts("Running treatment (#{inspect(treatment_mod)})…")
    treatment = Eval.run(Keyword.put(base_opts, :reranker, treatment_mod))

    print_compare(baseline.summary, treatment.summary, sources, baseline_mod, treatment_mod)
    if opts[:verbose], do: print_per_item_diff(baseline.items, treatment.items, sources)
    if opts[:json], do: write_json(opts[:json], baseline, treatment, baseline_mod, treatment_mod)

    :ok
  end

  defp build_base_opts(opts) do
    {random?, seed} = resolve_random(opts[:random], opts[:seed])

    [sources: parse_sources(opts[:source])]
    |> maybe_put(:file, opts[:file])
    |> maybe_put(:top_k, opts[:top_k])
    |> maybe_put(:limit, opts[:limit])
    |> maybe_put(:random, random?)
    |> maybe_put(:seed, seed)
    |> maybe_put(:concurrency, opts[:concurrency])
  end

  defp resolve_random(nil, nil), do: {nil, nil}
  defp resolve_random(true, nil), do: {true, :erlang.system_time(:microsecond)}
  defp resolve_random(_, seed) when is_integer(seed), do: {true, seed}
  defp resolve_random(random, seed), do: {random, seed}

  defp resolve_module(nil, default), do: default

  defp resolve_module(str, _default) when is_binary(str) do
    mod =
      str
      |> String.trim()
      |> String.trim_leading("Elixir.")
      |> then(&("Elixir." <> &1))
      |> String.to_atom()

    if !Code.ensure_loaded?(mod) do
      Mix.raise("Reranker module #{inspect(mod)} could not be loaded")
    end

    if !function_exported?(mod, :rerank, 3) do
      Mix.raise("Module #{inspect(mod)} does not export rerank/3 (not a Reranker behaviour)")
    end

    mod
  end

  defp default_reranker() do
    :sanbase
    |> Application.get_env(Reranker, [])
    |> Keyword.get(:default, Sanbase.Knowledge.Reranker.Noop)
  end

  defp parse_sources(nil), do: [:faq, :academy, :insights]
  defp parse_sources("all"), do: [:faq, :academy, :insights]

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

  defp print_compare(baseline, treatment, sources, base_mod, treat_mod) do
    IO.puts("")
    IO.puts("=== Knowledge Eval Compare ===")
    IO.puts("baseline:  #{inspect(base_mod)}")
    IO.puts("treatment: #{inspect(treat_mod)}")

    Enum.each(sources, fn src ->
      b = Map.get(baseline, src, %{evaluated: 0})
      t = Map.get(treatment, src, %{evaluated: 0})

      IO.puts("")
      IO.puts("[#{src}] evaluated=#{b[:evaluated]}")

      if b[:evaluated] == 0 do
        IO.puts("  (no scored items)")
      else
        IO.puts(
          "  " <>
            pad("metric", 18) <>
            pad("baseline", 12) <>
            pad("treatment", 12) <>
            "delta"
        )

        Enum.each(@metric_rows, fn {key, label} ->
          bv = b[key]
          tv = t[key]

          IO.puts(
            "  " <>
              pad(label, 18) <>
              pad(fmt(bv), 12) <>
              pad(fmt(tv), 12) <>
              fmt_delta(tv, bv)
          )
        end)
      end
    end)

    IO.puts("")
  end

  defp print_per_item_diff(baseline_items, treatment_items, sources) do
    IO.puts("=== Per-question rank changes ===")

    baseline_items
    |> Enum.zip(treatment_items)
    |> Enum.each(fn {b, t} ->
      lines =
        sources
        |> Enum.map(&rank_diff_line(&1, b, t))
        |> Enum.reject(&is_nil/1)

      if lines != [] do
        IO.puts("")
        IO.puts("#{b.id}: #{b.question}")
        Enum.each(lines, &IO.puts/1)
      end
    end)

    IO.puts("")
  end

  defp rank_diff_line(src, b, t) do
    br = first_rank(Map.get(b, src))
    tr = first_rank(Map.get(t, src))

    cond do
      is_nil(br) and is_nil(tr) -> nil
      br == tr -> nil
      true -> "  [#{src}] rank #{fmt_rank(br)} -> #{fmt_rank(tr)}#{rank_delta_str(br, tr)}"
    end
  end

  defp first_rank(%{first_rank: r}), do: r
  defp first_rank(_), do: nil

  defp fmt_rank(nil), do: "n/a"
  defp fmt_rank(0), do: "miss"
  defp fmt_rank(r) when is_integer(r), do: Integer.to_string(r)

  defp rank_delta_str(b, t) when is_integer(b) and is_integer(t) do
    cond do
      b == 0 and t == 0 -> ""
      b == 0 -> " (found)"
      t == 0 -> " (lost)"
      t < b -> " (up #{b - t})"
      t > b -> " (down #{t - b})"
      true -> ""
    end
  end

  defp rank_delta_str(_, _), do: ""

  defp write_json(path, baseline, treatment, base_mod, treat_mod) do
    File.mkdir_p!(Path.dirname(path))

    payload = %{
      baseline: %{
        reranker: inspect(base_mod),
        summary: baseline.summary,
        items: baseline.items
      },
      treatment: %{
        reranker: inspect(treat_mod),
        summary: treatment.summary,
        items: treatment.items
      },
      delta: build_delta(baseline.summary, treatment.summary)
    }

    File.write!(path, Jason.encode!(payload, pretty: true))
    IO.puts("JSON written to #{path}")
  end

  defp build_delta(baseline, treatment) do
    Map.new(baseline, fn {src, b} ->
      t = Map.get(treatment, src, %{evaluated: 0})

      diffs =
        Map.new(@metric_rows, fn {key, _label} ->
          {key, delta_value(t[key], b[key])}
        end)

      {src, diffs}
    end)
  end

  defp delta_value(t, b) when is_number(t) and is_number(b), do: t - b
  defp delta_value(_, _), do: nil

  defp pad(str, width) do
    str = to_string(str)

    if String.length(str) >= width do
      str <> " "
    else
      String.pad_trailing(str, width)
    end
  end

  defp fmt_delta(t, b) when is_number(t) and is_number(b) do
    diff = t - b
    sign = if diff >= 0, do: "+", else: ""
    "#{sign}#{:erlang.float_to_binary(diff / 1, decimals: 3)}"
  end

  defp fmt_delta(_, _), do: "n/a"

  defp fmt(num) when is_number(num), do: :erlang.float_to_binary(num / 1, decimals: 3)
  defp fmt(_), do: "n/a"
end
