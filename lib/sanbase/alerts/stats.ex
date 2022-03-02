defmodule Sanbase.Alerts.Stats do
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Alert.HistoricalActivity

  def fired_alerts_24h(user_id) do
    now = Timex.now()
    day_ago = Timex.shift(now, days: -1)
    week_ago = Timex.shift(now, days: -7)
    query = from(ha in HistoricalActivity, where: ha.user_id == ^user_id, select: ha.data)
    day_ago_query = from(ha in query, where: ha.triggered_at > ^day_ago)
    week_ago_query = from(ha in query, where: ha.triggered_at > ^week_ago)

    stats_day = compute_stats(day_ago_query)
    stats_week = compute_stats(week_ago_query)
    compute(stats_day, stats_week)
  end

  defp compute([], _), do: %{}
  defp compute(_, []), do: %{}

  defp compute(stats_day, stats_week) do
    stats_week =
      stats_week
      |> Enum.reduce(%{}, fn {slug, alerts}, acc -> Map.merge(acc, %{slug => alerts}) end)

    total_fired =
      stats_day
      |> Enum.reduce(0, fn {_slug, alerts}, count -> count + length(alerts.alerts) end)

    total_fired_weekly =
      stats_week
      |> Enum.reduce(0, fn {_slug, alerts}, count -> count + length(alerts.alerts) end)

    total_fired_weekly_avg = total_fired_weekly / 7

    total_fired_percent_change =
      percent_change(total_fired_weekly_avg, total_fired) |> Float.round(2)

    fired_alerts =
      stats_day
      |> Enum.map(fn {slug, fired_data} ->
        avg_week = stats_week[slug].count / 7
        percent_change = percent_change(avg_week, fired_data.count) |> Float.round(2)
        alerts_types = fired_data.alerts |> Enum.map(&alert_type(&1))

        %{
          slug: slug,
          count: fired_data.count,
          percent_change: percent_change,
          alert_types: alerts_types
        }
      end)

    %{
      total_fired: total_fired,
      total_fired_weekly_avg: total_fired_weekly_avg,
      total_fired_percent_change: total_fired_percent_change,
      data: fired_alerts
    }
  end

  defp alert_type(alert) do
    case alert.type do
      "metric_signal" -> alert.metric
      "daily_metric_signal" -> alert.metric
      "signal_data" -> alert.signal
      _ -> alert.type
    end
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp compute_stats(query) do
    all = Repo.all(query)

    screener =
      all
      |> Enum.filter(fn data ->
        not is_nil(data["user_trigger_data"]["default"]) and
          data["user_trigger_data"]["default"]["type"] == "screener_signal"
      end)

    metric_or_signal =
      all
      |> Enum.filter(fn data ->
        Enum.all?(data["user_trigger_data"], fn {_, utd} ->
          utd["type"] in ["metric_signal", "daily_metric_signal", "signal_data"]
        end)
      end)

    screener =
      Enum.flat_map(screener, fn data ->
        data["user_trigger_data"]
        |> Enum.flat_map(fn {_, utd} ->
          alert = %{type: utd["type"]}
          Enum.map(utd["added_slugs"], fn slug -> {slug, alert} end)
        end)
      end)

    metric_or_signal =
      metric_or_signal
      |> Enum.flat_map(fn data ->
        data["user_trigger_data"]
        |> Enum.map(fn {slug, utd} ->
          alert = %{
            type: utd["type"],
            metric: utd["metric"],
            signal: utd["signal"]
          }

          {slug, alert}
        end)
      end)

    all = screener ++ metric_or_signal

    all
    |> Enum.reduce(%{}, fn {slug, alert}, acc ->
      Map.update(acc, slug, [alert], fn old -> old ++ [alert] end)
    end)
    |> Enum.reduce(%{}, fn {slug, alerts}, acc ->
      Map.update(acc, slug, alerts, fn old -> old ++ alerts end)
    end)
    |> Enum.into(%{}, fn {slug, alerts} ->
      {slug, %{alerts: alerts, count: length(alerts)}}
    end)
    |> Enum.sort_by(fn {_slug, data} -> data.count end, :desc)
  end

  defp percent_change(old, new) do
    (new - old) / old * 100
  end
end
