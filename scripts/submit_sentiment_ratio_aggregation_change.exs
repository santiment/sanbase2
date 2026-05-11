# Script to submit change requests for sentiment ratio metrics
# that are unverified and have default_aggregation = sum.
# Changes default_aggregation from sum to avg.
#
# Run with: mix run scripts/submit_sentiment_ratio_aggregation_change.exs

alias Sanbase.Metric.Registry
alias Sanbase.Metric.Registry.ChangeSuggestion

import Ecto.Query

submitted_by = "ivan.i@santiment.net"
notes = "Change default aggregation from sum to avg for sentiment ratio metrics"

# Query metrics that are:
# 1. Unverified (is_verified == false)
# 2. Have both "sentiment" and "ratio" in their name
# 3. Have default_aggregation == "sum"
metrics =
  from(m in Registry,
    where:
      m.is_verified == false and
        like(m.metric, "%sentiment%") and
        like(m.metric, "%ratio%") and
        m.default_aggregation == "sum"
  )
  |> Sanbase.Repo.all()

IO.puts("Found #{length(metrics)} metrics matching criteria:\n")

for m <- metrics do
  IO.puts("  - #{m.metric} (id: #{m.id}, aggregation: #{m.default_aggregation})")
end

IO.puts("")

results =
  Enum.map(metrics, fn metric ->
    params = %{"default_aggregation" => "avg"}

    case ChangeSuggestion.create_change_suggestion(metric, params, notes, submitted_by) do
      {:ok, suggestion} ->
        IO.puts(
          "[OK] Change request created for #{metric.metric} (suggestion id: #{suggestion.id})"
        )

        {:ok, metric.metric}

      {:error, error} ->
        IO.puts("[ERROR] Failed to create change request for #{metric.metric}: #{inspect(error)}")
        {:error, metric.metric, error}
    end
  end)

successes = Enum.count(results, &match?({:ok, _}, &1))
failures = Enum.count(results, &match?({:error, _, _}, &1))

IO.puts("\nDone. #{successes} change requests created, #{failures} failures.")
