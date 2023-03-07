defmodule Sanbase.RunExamples do
  @queries [
    :basic_metric_queries,
    :trending_words,
    :top_holders
  ]
  def run do
    for q <- @queries, do: do_run(q)
  end

  defp do_run(:basic_metric_queries) do
    for metric <- ["price_usd", "daily_active_addresses", "active_addresses_24h", "dev_activity"] do
      {:ok, [_ | _]} =
        Sanbase.Metric.timeseries_data(
          metric,
          %{slug: "ethereum"},
          Timex.shift(Timex.now(), days: -7),
          Timex.now(),
          "1d"
        )

      {:ok, _} =
        Sanbase.Metric.aggregated_timeseries_data(
          metric,
          %{slug: "ethereum"},
          Timex.shift(Timex.now(), days: -2),
          Timex.now()
        )
    end
  end

  defp do_run(:trending_words) do
    {:ok, [_ | _]} =
      Sanbase.SocialData.TrendingWords.get_project_trending_history(
        "bitcoin",
        ~U[2023-01-23 00:00:00Z],
        ~U[2023-01-30 00:00:00Z],
        "1d",
        10
      )

    {:ok, [_ | _]} =
      Sanbase.SocialData.TrendingWords.get_word_trending_history(
        "bitcoin",
        ~U[2023-01-01 00:00:00Z],
        ~U[2023-01-30 00:00:00Z],
        "1d",
        10
      )

    {:ok, %{}} =
      Sanbase.SocialData.TrendingWords.get_trending_words(
        ~U[2023-01-01 00:00:00Z],
        ~U[2023-01-05 00:00:00Z],
        "6h",
        10
      )
  end

  defp do_run(:top_holders) do
  end
end
