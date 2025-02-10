defmodule Sanbase.Embed do
  @moduledoc false
  def create_charts_link(metric, slug) do
    now =
      DateTime.utc_now()
      |> Timex.shift(minutes: 10)
      |> Sanbase.DateTimeUtils.round_datetime(second: 600)
      |> Timex.set(microsecond: {0, 0})

    six_months_ago =
      now
      |> Timex.shift(months: -6)
      |> Timex.set(microsecond: {0, 0})

    now_iso = DateTime.to_iso8601(now)
    six_months_ago_iso = DateTime.to_iso8601(six_months_ago)

    settings_json = Jason.encode!(%{slug: slug, from: six_months_ago_iso, to: now_iso})

    metrics = if metric == "price_usd", do: [metric], else: ["price_usd", metric]
    wax = metrics |> Enum.with_index() |> Map.new() |> Map.values()

    widgets_json =
      Jason.encode!([
        %{widget: "ChartWidget", wm: metrics, whm: [], wax: wax, wpax: [], wc: ["#26C953"]}
      ])

    url = URI.encode("/charts?settings=#{settings_json}&widgets=#{widgets_json}")
    Sanbase.ShortUrl.create(%{full_url: url})
  end
end
