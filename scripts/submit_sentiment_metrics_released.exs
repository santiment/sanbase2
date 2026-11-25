# Submit change requests to promote the bullish/bearish/neutral sentiment
# metrics (and the related sentiment ratio and labeled docs count metrics)
# from status "beta" to "released".
#
# Selected metrics: every metric registry row with status "beta" whose name
# matches one of @name_patterns (Postgres regex):
#   - sentiment_{bullish,bearish,neutral}_*       (e.g. sentiment_bullish_twitter, sentiment_bearish_total)
#   - sentiment_{positive,negative,neutral}_ratio_* (e.g. sentiment_positive_ratio_twitter_1h)
#   - {positive,negative,neutral}_docs_count_*    (e.g. negative_docs_count_twitter)
#
# Farcaster metrics (any name containing "farcaster") are NOT released, they stay in beta.
#
# Metrics that already have a pending change request setting status to
# "released" are skipped, so the script is safe to re-run.
#
# Like the other metric registry scripts, this only creates change requests
# (status "pending_approval"). They still have to be approved in the admin UI.
#
# The output also lists other "beta" sentiment/docs metrics that are NOT
# selected, so the selection can be reviewed during the dry run.
#
# Run:
#   mix run scripts/submit_sentiment_metrics_released.exs --dry-run
#   mix run scripts/submit_sentiment_metrics_released.exs

defmodule SubmitSentimentMetricsReleased do
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Metric.Registry
  alias Sanbase.Metric.Registry.ChangeSuggestion

  @submitted_by "ivan.i@santiment.net"
  @notes "Promote bullish/bearish/neutral sentiment metrics from beta to released"
  @params %{"status" => "released"}
  @from_status "beta"
  # Farcaster metrics stay in beta
  @excluded_substring "farcaster"

  @name_patterns [
    "^sentiment_(bullish|bearish|neutral)_",
    "^sentiment_(positive|negative|neutral)_ratio_",
    "^(positive|negative|neutral)_docs_count_"
  ]

  def run(opts \\ []) do
    dry_run? = Keyword.get(opts, :dry_run, false)

    IO.puts(if dry_run?, do: "=== DRY RUN: nothing will be written ===\n", else: "")

    metrics = fetch_metrics()
    {to_skip, to_submit} = Enum.split_with(metrics, &pending_release_suggestion?/1)

    IO.puts("Found #{length(metrics)} '#{@from_status}' metrics matching the patterns.")
    IO.puts("  - #{length(to_submit)} to submit")
    IO.puts("  - #{length(to_skip)} skipped (pending 'released' change request exists)\n")

    Enum.each(to_skip, fn m ->
      IO.puts("[SKIP] #{m.metric} (id: #{m.id}) — already has a pending 'released' request")
    end)

    results =
      Enum.map(to_submit, fn m ->
        if dry_run?, do: validate(m), else: submit(m)
      end)

    print_not_selected(metrics)

    ok = Enum.count(results, &(&1 == :ok))
    err = Enum.count(results, &(&1 == :error))

    if dry_run? do
      IO.puts(
        "\nDry run done. #{ok} would be created, #{err} invalid, #{length(to_skip)} skipped."
      )
    else
      IO.puts("\nDone. #{ok} created, #{err} failed, #{length(to_skip)} skipped.")
    end
  end

  defp fetch_metrics() do
    from(m in Registry,
      where:
        m.status == ^@from_status and
          fragment("? ~ ?", m.metric, ^name_regex()) and
          not like(m.metric, ^"%#{@excluded_substring}%"),
      order_by: [asc: m.metric, asc: m.id]
    )
    |> Repo.all()
  end

  defp name_regex(), do: Enum.map_join(@name_patterns, "|", &"(#{&1})")

  # Other beta metrics that look sentiment-related but are not selected.
  # Printed only so the selection can be reviewed; nothing is done with them.
  defp print_not_selected(selected) do
    selected_ids = MapSet.new(selected, & &1.id)

    others =
      from(m in Registry,
        where:
          m.status == ^@from_status and
            (like(m.metric, "%sentiment%") or like(m.metric, "%docs_count%")),
        order_by: [asc: m.metric, asc: m.id]
      )
      |> Repo.all()
      |> Enum.reject(&MapSet.member?(selected_ids, &1.id))

    IO.puts("\nOther '#{@from_status}' sentiment/docs metrics NOT selected: #{length(others)}")
    Enum.each(others, &IO.puts("  - #{&1.metric} (id: #{&1.id})"))
  end

  defp pending_release_suggestion?(%Registry{id: id}) do
    from(cs in ChangeSuggestion,
      where: cs.metric_registry_id == ^id and cs.status == "pending_approval",
      select: cs.changes
    )
    |> Repo.all()
    |> Enum.any?(&sets_status_released?/1)
  end

  defp sets_status_released?(encoded_changes) do
    match?(
      %{status: {:changed, {:primitive_change, _, "released"}}},
      ChangeSuggestion.decode_changes(encoded_changes)
    )
  rescue
    _ -> false
  end

  defp validate(metric) do
    case Registry.changeset(metric, @params) do
      %{valid?: true} ->
        IO.puts("[DRY] #{metric.metric} (id: #{metric.id}): #{metric.status} -> released")
        :ok

      changeset ->
        IO.puts("[INVALID] #{metric.metric} (id: #{metric.id}): #{inspect(changeset.errors)}")
        :error
    end
  end

  defp submit(metric) do
    case ChangeSuggestion.create_change_suggestion(metric, @params, @notes, @submitted_by) do
      {:ok, suggestion} ->
        IO.puts("[OK] #{metric.metric} (id: #{metric.id}, suggestion id: #{suggestion.id})")
        :ok

      {:error, error} ->
        IO.puts("[ERROR] #{metric.metric} (id: #{metric.id}): #{inspect(error)}")
        :error
    end
  end
end

{opts, _, _} = OptionParser.parse(System.argv(), strict: [dry_run: :boolean])

SubmitSentimentMetricsReleased.run(opts)
