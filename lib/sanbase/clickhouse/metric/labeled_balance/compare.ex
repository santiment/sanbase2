defmodule Sanbase.Clickhouse.MetricAdapter.LabeledBalance.Compare do
  @moduledoc ~s"""
  Compare the legacy (precomputed) and the delta-based labelled balances for the same
  request. Used before enabling the delta source for a slug.

      Compare.run(
        "labelled_historical_balance",
        %{slug: "ethereum"},
        ~U[2026-01-01 00:00:00Z],
        ~U[2026-10-19 00:00:00Z],
        "1d",
        additional_filters: [label_fqn: "santiment/binance:v1"]
      )

  A slug list is compared per slug with `timeseries_data_per_slug`. The data of the last
  3 hours is skipped, as the two sources are not updated at the same time.
  """

  alias Sanbase.Clickhouse.MetricAdapter

  @default_tolerance 1.0e-6
  @freshness_lag_seconds 3 * 3600
  @max_diffs 20

  def run(metric, selector, from, to, interval, opts \\ []) do
    to = Enum.min([to, DateTime.add(DateTime.utc_now(), -@freshness_lag_seconds)], DateTime)
    tolerance = Keyword.get(opts, :tolerance, @default_tolerance)
    opts = Keyword.delete(opts, :tolerance)

    with {:ok, legacy} <- fetch(metric, selector, from, to, interval, opts ++ [source: :legacy]),
         {:ok, delta} <- fetch(metric, selector, from, to, interval, opts ++ [source: :delta]) do
      {:ok, compare(legacy, delta, tolerance)}
    end
  end

  @doc ~s"""
  Compare two maps of `{slug, datetime} => value`.
  """
  def compare(legacy, delta, tolerance \\ @default_tolerance) do
    keys = MapSet.union(MapSet.new(Map.keys(legacy)), MapSet.new(Map.keys(delta)))

    diffs =
      for key <- Enum.sort_by(keys, fn {slug, dt} -> {slug, DateTime.to_unix(dt)} end),
          {legacy_value, delta_value} = {Map.get(legacy, key), Map.get(delta, key)},
          relative_diff = relative_diff(legacy_value, delta_value),
          relative_diff > tolerance do
        {slug, datetime} = key

        %{
          slug: slug,
          datetime: datetime,
          legacy: legacy_value,
          delta: delta_value,
          relative_diff: relative_diff
        }
      end

    %{
      points: MapSet.size(keys),
      differ: length(diffs),
      only_legacy: Enum.count(diffs, &is_nil(&1.delta)),
      only_delta: Enum.count(diffs, &is_nil(&1.legacy)),
      max_relative_diff: diffs |> Enum.map(& &1.relative_diff) |> Enum.max(fn -> 0.0 end),
      diffs: Enum.take(diffs, @max_diffs)
    }
  end

  # Private functions

  defp fetch(metric, %{slug: slugs} = selector, from, to, interval, opts) when is_list(slugs) do
    with {:ok, data} <-
           MetricAdapter.timeseries_data_per_slug(metric, selector, from, to, interval, opts) do
      {:ok,
       for(
         %{datetime: datetime, data: list} <- data,
         %{slug: slug, value: value} <- list,
         into: %{},
         do: {{slug, datetime}, value}
       )}
    end
  end

  defp fetch(metric, %{slug: slug} = selector, from, to, interval, opts) do
    with {:ok, data} <- MetricAdapter.timeseries_data(metric, selector, from, to, interval, opts) do
      {:ok,
       Map.new(data, fn %{datetime: datetime, value: value} -> {{slug, datetime}, value} end)}
    end
  end

  # A missing point counts as a difference. `:infinity` is greater than any number
  defp relative_diff(nil, _), do: :infinity
  defp relative_diff(_, nil), do: :infinity
  defp relative_diff(a, b) when a == b, do: 0.0

  defp relative_diff(a, b) do
    abs(a - b) / max(abs(a), abs(b))
  end
end
