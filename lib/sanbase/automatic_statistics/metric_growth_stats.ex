defmodule MetricGrowthStats do
  @moduledoc """
  Module for calculating growth/consecutive changes stats for metrics returning top performers.
  """

  @doc """
  * current_to: End datetime till which we should measure the growth, default: start of today
  * interval_days: Interval in days for measuring the growth, default: 7 days
  * aggregation: All available agregations for metric, default: :avg
  * limit: number of max elements, default: 10
  * max_by: :change | :percent_change, default: :percent_change
  * threshold: Threshold for previous and current value, default: 0
  """

  def max_growth(metric, slugs, opts \\ []) do
    current_to = Keyword.get(opts, :current_to_datetime, Timex.beginning_of_day(Timex.now()))
    interval_days = Keyword.get(opts, :interval, 7)
    aggregation = Keyword.get(opts, :aggregation, :avg)
    limit = Keyword.get(opts, :limit, 10)
    max_by = Keyword.get(opts, :max_by, :percent_change)
    threshold = Keyword.get(opts, :threshold, 0)

    current_from = Timex.shift(current_to, days: -interval_days)

    {prev_from, prev_to} =
      {Timex.shift(current_to, days: -(2 * interval_days)),
       Timex.shift(current_to, days: -interval_days)}

    calculate_growth(metric, slugs, %{
      prev_from: prev_from,
      prev_to: prev_to,
      current_from: current_from,
      current_to: current_to,
      interval_days: interval_days,
      aggregation: aggregation
    })
    |> Enum.reduce(%{}, &Map.merge(&1, &2))
    |> Enum.filter(fn {_slug, data} -> data.previous > threshold && data.current > threshold end)
    |> Enum.sort_by(fn {_slug, change} -> change[max_by] end, :desc)
    |> Enum.take(limit)
  end

  defp calculate_growth("social_volume_total" = metric, slugs, %{
         prev_from: prev_from,
         prev_to: prev_to,
         current_from: current_from,
         current_to: current_to,
         interval_days: interval_days
       }) do
    slugs
    |> Enum.map(fn slug ->
      with {:ok, [%{value: p} | _]} when is_number(p) <-
             Sanbase.Metric.timeseries_data(
               metric,
               %{slug: slug},
               prev_from,
               prev_to,
               "#{interval_days}d"
             ),
           {:ok, [%{value: c} | _]} when is_number(c) <-
             Sanbase.Metric.timeseries_data(
               metric,
               %{slug: slug},
               current_from,
               current_to,
               "#{interval_days}d"
             ) do
        %{
          slug => %{
            previous: p,
            current: c,
            change: c - p,
            percent_change: Sanbase.Math.percent_change(p, c)
          }
        }
      else
        _ -> %{slug => %{previous: 0, current: 0, change: 0, percent_change: 0}}
      end
    end)
  end

  defp calculate_growth(metric, slugs, %{
         prev_from: prev_from,
         prev_to: prev_to,
         current_from: current_from,
         current_to: current_to,
         aggregation: aggregation
       }) do
    {:ok, previous} =
      Sanbase.Metric.aggregated_timeseries_data(
        metric,
        %{slug: slugs},
        prev_from,
        prev_to,
        aggregation
      )

    {:ok, current} =
      Sanbase.Metric.aggregated_timeseries_data(
        metric,
        %{slug: slugs},
        current_from,
        current_to,
        aggregation
      )

    current
    |> Enum.map(fn {slug, c} ->
      p = previous[slug]

      if c && p do
        %{
          slug => %{
            previous: p,
            current: c,
            change: c - p,
            percent_change: Sanbase.Math.percent_change(p, c)
          }
        }
      else
        %{slug => %{previous: 0, current: 0, change: 0, percent_change: 0}}
      end
    end)
  end
end
