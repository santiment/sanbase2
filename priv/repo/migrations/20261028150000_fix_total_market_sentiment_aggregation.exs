defmodule Sanbase.Repo.Migrations.FixTotalMarketSentimentAggregation do
  use Ecto.Migration

  # Total Market Sentiment is a bounded ratio:
  #
  #   (bullish - bearish) / (bullish + bearish)
  #
  # so every bucket value is in [-1, 1]. The metric is stored at 5m, which means
  # the daily value is the *mean* of the buckets, not their sum. With the default
  # aggregation set to `sum`, a single day resolves to ~224 (288 buckets x ~0.78)
  # instead of ~0.78, and `aggregatedTimeseriesData` to ~1357 for a week, which is
  # outside the metric's documented range.
  #
  # The runtime aggregation is read from the `metric_registry` row
  # (`Sanbase.Metric.Registry` -> `Sanbase.Clickhouse.MetricAdapter.Registry`),
  # not from the YAML spec or the checked-in fallback JSON, so the correction has
  # to be applied to the table.
  @metric "sentiment_bb_ratio_selective"

  def up() do
    execute("""
    UPDATE metric_registry
    SET default_aggregation = 'avg', updated_at = NOW()
    WHERE metric = '#{@metric}'
      AND data_type = 'timeseries'
      AND default_aggregation <> 'avg'
    """)
  end

  def down() do
    # Restore the previous, incorrect value so the migration stays reversible.
    execute("""
    UPDATE metric_registry
    SET default_aggregation = 'sum', updated_at = NOW()
    WHERE metric = '#{@metric}'
      AND data_type = 'timeseries'
    """)
  end
end
