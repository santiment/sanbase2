defmodule Sanbase.MetricGrowthStats do
  @moduledoc """
  Module for calculating growth/consecutive changes stats for metrics returning top performers.
  """

  @social_metrics Sanbase.SocialData.MetricAdapter.available_metrics()

  @doc """
  * end_datetime: End datetime till which we should measure the growth, default: Timex.now()
  * interval_days: Interval in days for measuring the growth, default: "7d"
  * aggregation: All available agregations for metric, default: nil
  * limit: Number of assets, default: 10
  * max_by: :change | :percent_change, default: :percent_change
  * threshold: Previous and current value should be bigger than provided threshold, default: 0
  """

  def max_growth(metric, slugs, opts \\ []) do
    current_to = Keyword.get(opts, :end_datetime, Timex.now())
    interval = Keyword.get(opts, :interval, "7d")
    interval_days = Sanbase.DateTimeUtils.str_to_days(interval)
    aggregation = Keyword.get(opts, :aggregation, nil)
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
      interval: interval,
      aggregation: aggregation
    })
    |> Enum.reduce(%{}, &Map.merge(&1, &2))
    |> Enum.filter(fn {_slug, data} -> data.previous > threshold && data.current > threshold end)
    |> Enum.sort_by(fn {_slug, change} -> change[max_by] end, :desc)
    |> Enum.take(limit)
  end

  defp calculate_growth(metric, slugs, %{
         prev_from: prev_from,
         prev_to: prev_to,
         current_from: current_from,
         current_to: current_to,
         interval: interval
       })
       when metric in @social_metrics do
    slugs
    |> Enum.map(fn slug ->
      with {:ok, [%{value: previous_value} | _]} when is_number(previous_value) <-
             Sanbase.Metric.timeseries_data(
               metric,
               %{slug: slug},
               prev_from,
               prev_to,
               interval
             ),
           {:ok, [%{value: current_value} | _]} when is_number(current_value) <-
             Sanbase.Metric.timeseries_data(
               metric,
               %{slug: slug},
               current_from,
               current_to,
               interval
             ) do
        %{
          slug => %{
            previous: previous_value,
            current: current_value,
            change: current_value - previous_value,
            percent_change: Sanbase.Math.percent_change(previous_value, current_value)
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
    {:ok, previous_data} =
      Sanbase.Metric.aggregated_timeseries_data(
        metric,
        %{slug: slugs},
        prev_from,
        prev_to,
        aggregation
      )

    {:ok, current_data} =
      Sanbase.Metric.aggregated_timeseries_data(
        metric,
        %{slug: slugs},
        current_from,
        current_to,
        aggregation
      )

    current_data
    |> Enum.map(fn {slug, current_value} ->
      previous_value = previous_data[slug]

      if current_value && previous_value do
        %{
          slug => %{
            previous: previous_value,
            current: current_value,
            change: current_value - previous_value,
            percent_change: Sanbase.Math.percent_change(previous_value, current_value)
          }
        }
      else
        %{slug => %{previous: 0, current: 0, change: 0, percent_change: 0}}
      end
    end)
  end
end
