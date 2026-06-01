defmodule Sanbase.Knowledge.FaqSync do
  @moduledoc """
  Move FAQ entries between environments via a JSON file — typically to copy
  production FAQs into a local/dev database for testing the knowledge bot.

  Two steps:

      # On a production pod (in iex), dump the live FAQs to a file:
      Sanbase.Knowledge.FaqSync.export_to_file("/tmp/faqs.json")

      # Locally, load that file (copy it over first):
      Sanbase.Knowledge.FaqSync.import_from_file("/tmp/faqs.json")
      Sanbase.Knowledge.Indexer.reindex(:faq)   # then re-embed locally

  Embeddings are intentionally NOT exported — they are re-generated locally
  with `Indexer.reindex(:faq)` (or `Faq.embed_all/0`) after import, using the
  local embedding key. Only question/answer/source_url/tags travel; the prod
  `id` is preserved so re-importing updates in place rather than duplicating.

  `import_from_file/1` refuses to run against a production database (same
  detection as `mix database_safety` — see `Sanbase.Utils.prod_db?/0`), so it
  can only ever write to a local/dev DB.
  """

  import Ecto.Query

  require Logger

  alias Sanbase.Knowledge.FaqEntry
  alias Sanbase.Repo

  @export_version 1

  @doc """
  Dump all non-deleted FAQ entries (question, answer_markdown, source_url,
  tags, and the original id) to `path` as JSON. Returns the count written.
  """
  @spec export_to_file(Path.t()) :: {:ok, %{path: Path.t(), count: non_neg_integer()}}
  def export_to_file(path) do
    faqs =
      from(e in FaqEntry, where: e.is_deleted == false, preload: [:tags])
      |> Repo.all()
      |> Enum.map(fn e ->
        %{
          id: e.id,
          question: e.question,
          answer_markdown: e.answer_markdown,
          source_url: e.source_url,
          tags: Enum.map(e.tags, & &1.name)
        }
      end)

    payload = %{version: @export_version, count: length(faqs), faqs: faqs}
    File.write!(path, Jason.encode!(payload, pretty: true))

    Logger.info("[FaqSync] exported #{length(faqs)} FAQ entries to #{path}")
    {:ok, %{path: path, count: length(faqs)}}
  end

  @doc """
  Load FAQ entries from a JSON file produced by `export_to_file/1` and upsert
  them into the local database (matched by id). Embeddings are left empty —
  run `Indexer.reindex(:faq)` afterwards.

  Raises if the target looks like a production database.
  """
  @spec import_from_file(Path.t()) ::
          {:ok,
           %{
             total: non_neg_integer(),
             inserted: non_neg_integer(),
             updated: non_neg_integer(),
             failed: non_neg_integer()
           }}
  def import_from_file(path) do
    ensure_not_prod!()

    %{"faqs" => faqs} = path |> File.read!() |> Jason.decode!()

    tally =
      Enum.reduce(faqs, %{inserted: 0, updated: 0, failed: 0}, fn faq, acc ->
        case upsert(faq) do
          {:ok, :inserted} -> Map.update!(acc, :inserted, &(&1 + 1))
          {:ok, :updated} -> Map.update!(acc, :updated, &(&1 + 1))
          {:error, reason} -> log_failure(faq, reason, acc)
        end
      end)

    result = Map.put(tally, :total, length(faqs))
    Logger.info("[FaqSync] imported FAQs: #{inspect(result)}")
    {:ok, result}
  end

  # Private functions

  defp upsert(%{"id" => id} = faq) do
    {entry, op} =
      case Repo.get(FaqEntry, id) do
        nil -> {%FaqEntry{id: id}, :inserted}
        existing -> {Repo.preload(existing, :tags), :updated}
      end

    attrs = %{
      "question" => faq["question"],
      "answer_markdown" => faq["answer_markdown"],
      "source_url" => faq["source_url"],
      "tags" => faq["tags"] || []
    }

    # Bypasses Faq.create_entry/2 on purpose: that path embeds each entry, but
    # we want embeddings regenerated in bulk locally via Indexer.reindex(:faq).
    entry
    |> FaqEntry.changeset(attrs)
    |> Repo.insert_or_update()
    |> case do
      {:ok, _} -> {:ok, op}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp log_failure(faq, reason, acc) do
    Logger.error("[FaqSync] failed to import FAQ id=#{faq["id"]}: #{inspect(reason)}")
    Map.update!(acc, :failed, &(&1 + 1))
  end

  # Refuse to write to a production database. Mirrors `mix database_safety`:
  # blocks when running in the :prod environment or when the configured DB /
  # DATABASE_URL points at production.
  defp ensure_not_prod!() do
    env = Sanbase.Utils.Config.module_get(Sanbase, :env)

    if env == :prod or Sanbase.Utils.prod_db?() do
      raise """
      Refusing to import FAQs: the target looks like a production database \
      (env=#{inspect(env)}, prod_db?=#{Sanbase.Utils.prod_db?()}).

      This loader only writes to local/dev databases. Make sure DATABASE_URL is \
      unset (or points to a local DB) and you are not on a production pod.
      """
    end

    :ok
  end
end
