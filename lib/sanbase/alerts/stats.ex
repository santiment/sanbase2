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

    stats_week =
      compute_stats(week_ago_query)
      |> Enum.reduce(%{}, fn {slug, alerts}, acc -> Map.merge(acc, %{slug => alerts}) end)

    total_fired =
      Enum.reduce(stats_day, 0, fn {_slug, alerts}, count -> count + length(alerts.alerts) end)

    total_fired_weekly_avg =
      Enum.reduce(stats_week, 0, fn {_slug, alerts}, count -> count + length(alerts.alerts) end) /
        7

    {total_fired_percent_change, direction_text} =
      percent_change(total_fired_weekly_avg, total_fired)

    total_fired_text =
      "#{Float.round(total_fired_percent_change, 2)}% #{direction_text} than weekly average"

    slugs = Enum.map(stats_day, fn {slug, _fired_data} -> slug end)
    slug_ticker_map = slug_ticker_map(slugs)

    fired_alerts =
      stats_day
      |> Enum.map(fn {slug, fired_data} ->
        avg_week = stats_week[slug].count / 7
        {percent, direction_text} = percent_change(avg_week, fired_data.count)
        percent_change = "#{Float.round(percent, 2)}%"
        alerts_types = fired_data.alerts |> Enum.map(&alert_type(&1))

        [
          slug_ticker_map[slug] || slug,
          fired_data.count,
          percent_change,
          alerts_types
        ]
      end)

    %{
      total_fired: total_fired,
      fired_alerts: fired_alerts
    }

    alerts_text =
      Enum.reduce(fired_alerts, "", fn [ticker, count, percent_change_text, metrics], acc_text ->
        acc_text <>
          "|#{String.pad_trailing(ticker, 5)}|#{String.pad_leading(Integer.to_string(count), 5)}|#{String.pad_leading(percent_change_text, 8)}\nMetrics: #{Enum.join(metrics, ", ")}\n\n"
      end)

    """
    *Stats for last 24 hours:*

    *Total alerts:* #{total_fired} _(#{total_fired_text})_

    ```
    |#{String.pad_trailing("Asset", 5)}|#{String.pad_leading("Count", 5)}|#{String.pad_leading("% change", 8)}|
    |#{String.pad_trailing("", 5, "_")}|#{String.pad_trailing("", 5, "_")}|#{String.pad_trailing("", 8, "_")}|
    #{alerts_text}
    ```
    """
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

  defp slug_ticker_map(slugs) do
    slugs
    |> Sanbase.Model.Project.tickers_by_slug_list()
    |> Enum.into(%{}, fn {t, s} -> {s, t} end)
  end

  def compute_stats(query) do
    Repo.all(query)
    |> Enum.flat_map(fn data ->
      data["user_trigger_data"]
      |> Enum.reduce(%{}, fn {slug, utd}, acc ->
        alert = %{
          type: utd["type"],
          metric: utd["metric"],
          signal: utd["signal"]
        }

        Map.update(acc, slug, [alert], fn old -> old ++ [alert] end)
      end)
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
    if new - old > 0 do
      {(new - old) / old * 100, "more"}
    else
      {(old - new) / old * 100, "less"}
    end
  end
end
