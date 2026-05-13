# Submit change requests to promote sentiment/social/docs metrics
# from status "alpha" to "beta".
#
# Run with: mix run scripts/submit_sentiment_beta_metrics_access.exs
# Or paste into iex.

defmodule PromoteSentimentMetrics do
  import Ecto.Query

  alias Sanbase.Metric.Registry
  alias Sanbase.Metric.Registry.ChangeSuggestion

  @submitted_by "ivan.i@santiment.net"
  @notes "Promote sentiment/social/docs metrics from alpha to beta access"
  @params %{"status" => "beta"}

  def run do
    metrics = fetch_metrics()

    IO.puts("Found #{length(metrics)} metrics:\n")
    Enum.each(metrics, &IO.puts("  - #{&1.metric} (id: #{&1.id})"))
    IO.puts("")

    {ok, err} = Enum.split_with(metrics, &submit/1)

    IO.puts("\nDone. #{length(ok)} created, #{length(err)} failed.")
  end

  defp fetch_metrics do
    from(m in Registry,
      where:
        m.status == "alpha" and
          (like(m.metric, "%sentiment%") or
             like(m.metric, "%social%") or
             like(m.metric, "%docs%"))
    )
    |> Sanbase.Repo.all()
  end

  defp submit(metric) do
    case ChangeSuggestion.create_change_suggestion(metric, @params, @notes, @submitted_by) do
      {:ok, suggestion} ->
        IO.puts("[OK] #{metric.metric} (suggestion id: #{suggestion.id})")
        true

      {:error, error} ->
        IO.puts("[ERROR] #{metric.metric}: #{inspect(error)}")
        false
    end
  end
end

PromoteSentimentMetrics.run()
