defmodule SanbaseWeb.Admin.UserOverview.Flags do
  @moduledoc """
  Heuristics that flag a user as a potential abuser based on the volume and
  depth of what they've created. Used by both the per-user overview and the
  rankings page so the two stay consistent.

  Thresholds are module attributes — bump them here as usage grows. Team
  (`@santiment.net`) users are excluded upstream and are never flagged.
  """

  # A single chart with this many metrics is the "286 widgets / 900+ metrics" case.
  @huge_chart_metrics 500
  # Below "huge" but still unusually deep for a single chart.
  @deep_chart_metrics 100
  @many_charts 50
  @huge_watchlist_assets 500
  @high_total_creations 200
  @max_api_keys 10

  @depth_flags [:huge_chart, :deep_chart, :many_charts, :huge_watchlist, :high_total]

  @typedoc "A flag is `{key, human_readable_reason}`."
  @type flag :: {atom(), String.t()}

  @typedoc """
  The minimal set of stats needed to evaluate the flags. Both the overview and
  a single rankings row can be reduced to this shape.
  """
  @type stats :: %{
          required(:charts) => non_neg_integer(),
          required(:max_chart_metrics) => non_neg_integer(),
          required(:max_watchlist_assets) => non_neg_integer(),
          required(:total_creations) => non_neg_integer(),
          required(:api_keys) => non_neg_integer(),
          required(:is_paid) => boolean()
        }

  @spec compute(stats()) :: [flag()]
  def compute(stats) do
    flags =
      []
      |> add(
        stats.max_chart_metrics > @huge_chart_metrics,
        {:huge_chart,
         "Has a chart with #{stats.max_chart_metrics} metrics (> #{@huge_chart_metrics})"}
      )
      |> add(
        stats.max_chart_metrics > @deep_chart_metrics and
          stats.max_chart_metrics <= @huge_chart_metrics,
        {:deep_chart,
         "Has a chart with #{stats.max_chart_metrics} metrics (> #{@deep_chart_metrics})"}
      )
      |> add(
        stats.charts > @many_charts,
        {:many_charts, "Created #{stats.charts} charts (> #{@many_charts})"}
      )
      |> add(
        stats.max_watchlist_assets > @huge_watchlist_assets,
        {:huge_watchlist,
         "Has a watchlist/screener with #{stats.max_watchlist_assets} assets (> #{@huge_watchlist_assets})"}
      )
      |> add(
        stats.total_creations > @high_total_creations,
        {:high_total, "#{stats.total_creations} total creations (> #{@high_total_creations})"}
      )
      |> add(
        stats.api_keys >= @max_api_keys,
        {:max_api_keys, "Reached the API key limit (#{stats.api_keys})"}
      )

    flags
    |> add(
      not stats.is_paid and Enum.any?(flags, fn {key, _} -> key in @depth_flags end),
      {:free_power_user, "Unpaid user with heavy usage"}
    )
    |> Enum.reverse()
  end

  defp add(list, true, flag), do: [flag | list]
  defp add(list, false, _flag), do: list
end
