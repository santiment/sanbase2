defmodule Mix.Tasks.KnowledgeReindex do
  @moduledoc """
  Re-embed the knowledge indexes (FAQ, Insight, Academy) via
  `Sanbase.Knowledge.Indexer`.

  ## Usage

      mix knowledge_reindex
      mix knowledge_reindex --source academy
      mix knowledge_reindex --source faq,insight
      mix knowledge_reindex --source academy --branch production --force
      mix knowledge_reindex --source academy --dry-run

  ## Options

    * `--source`  - comma-separated subset of `faq,insight,academy`; defaults to all
    * `--branch`  - Academy: GitHub branch to index (default `production`)
    * `--force`   - Academy: reindex even if the content SHA is unchanged
    * `--dry-run` - Academy: fetch + chunk but do not write embeddings
  """

  use Mix.Task

  @shortdoc "Re-embed FAQ / Insight / Academy knowledge indexes"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [source: :string, branch: :string, force: :boolean, dry_run: :boolean]
      )

    if invalid != [], do: Mix.raise("Invalid flags: #{inspect(invalid)}")
    if rest != [], do: Mix.raise("Unexpected arguments: #{inspect(rest)}")

    sources = parse_sources(opts[:source])
    reindex_opts = Keyword.take(opts, [:branch, :force, :dry_run])

    sources
    |> Sanbase.Knowledge.Indexer.reindex(reindex_opts)
    |> print_summary()

    :ok
  end

  defp parse_sources(nil), do: Sanbase.Knowledge.Indexer.sources()

  defp parse_sources(str) when is_binary(str) do
    allowed = Sanbase.Knowledge.Indexer.sources()

    str
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(fn src ->
      atom = String.to_existing_atom(src)

      if atom in allowed do
        atom
      else
        Mix.raise("Unsupported --source #{inspect(src)}. Allowed: #{Enum.join(allowed, ",")}")
      end
    end)
  rescue
    ArgumentError ->
      Mix.raise(
        "Unsupported --source #{inspect(str)}. Allowed: #{Enum.join(Sanbase.Knowledge.Indexer.sources(), ",")}"
      )
  end

  defp print_summary(results) do
    IO.puts("")
    IO.puts("=== Knowledge Reindex Summary ===")

    Enum.each(results, fn {source, %{status: status, took_ms: ms} = r} ->
      line = "[#{source}] #{status} (#{ms} ms)"
      line = if r.error, do: "#{line} error=#{inspect(r.error)}", else: line
      IO.puts(line)
    end)

    IO.puts("")
  end
end
