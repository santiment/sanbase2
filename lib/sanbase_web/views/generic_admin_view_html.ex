defmodule SanbaseWeb.GenericAdminHTML do
  use SanbaseWeb, :html

  use PhoenixHTMLHelpers

  embed_templates "../templates/generic_admin_html/*"

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :href, :string, default: nil
  attr :accent, :string, default: nil

  def stat_card(assigns) do
    ~H"""
    <.link
      :if={@href}
      navigate={@href}
      class="flex items-baseline justify-between gap-2 bg-base-100 border border-base-300 hover:border-base-content/30 rounded px-2 py-1 transition-colors"
    >
      <span class="text-xs text-base-content/60 truncate">{@label}</span>
      <span class={["text-sm font-semibold tabular-nums", @accent || "text-base-content"]}>
        {format_value(@value)}
      </span>
    </.link>
    <div
      :if={!@href}
      class="flex items-baseline justify-between gap-2 bg-base-100 border border-base-300 rounded px-2 py-1"
    >
      <span class="text-xs text-base-content/60 truncate">{@label}</span>
      <span class={["text-sm font-semibold tabular-nums", @accent || "text-base-content"]}>
        {format_value(@value)}
      </span>
    </div>
    """
  end

  defp format_value(n) when is_integer(n) and n >= 1_000_000,
    do: "#{Float.round(n / 1_000_000, 1)}M"

  defp format_value(n) when is_integer(n) and n >= 1_000, do: "#{Float.round(n / 1_000, 1)}k"
  defp format_value(n) when is_integer(n), do: Integer.to_string(n)
  defp format_value(other), do: to_string(other)

  attr :label, :string, required: true
  attr :series, :list, required: true

  def sparkline(assigns) do
    series = assigns.series
    n = length(series)
    today = Date.utc_today()
    start_date = Date.add(today, -(n - 1))
    dates = for i <- 0..(n - 1), do: Date.add(start_date, i)
    pairs = Enum.zip(dates, series)

    max = if series == [], do: 0, else: Enum.max(series)
    min = if series == [], do: 0, else: Enum.min(series)
    total = Enum.sum(series)
    last = List.last(series) || 0

    {points, area, coords} = sparkline_paths(series, 200, 56, 28, 8)

    hovers =
      pairs
      |> Enum.zip(coords)
      |> Enum.map(fn {{date, value}, {x, _y}} ->
        %{date: Date.to_iso8601(date), value: value, x: x}
      end)

    assigns =
      assign(assigns,
        total: total,
        last: last,
        max: max,
        min: min,
        start_date: start_date,
        end_date: today,
        points: points,
        area: area,
        coords: coords,
        hovers: hovers
      )

    ~H"""
    <div class="bg-base-100 border border-base-300 rounded px-3 py-2 flex flex-col gap-1">
      <div class="flex items-baseline justify-between gap-2">
        <span class="text-xs text-base-content/60 truncate">{@label}</span>
        <span class="text-sm font-semibold tabular-nums text-base-content">
          {format_value(@total)}
        </span>
      </div>
      <svg
        viewBox="0 0 200 64"
        class="w-full h-16"
        preserveAspectRatio="none"
      >
        <line
          x1="28"
          y1="8"
          x2="200"
          y2="8"
          stroke="currentColor"
          stroke-width="0.5"
          stroke-dasharray="2 2"
          class="text-base-content/15"
        />
        <line
          x1="28"
          y1="56"
          x2="200"
          y2="56"
          stroke="currentColor"
          stroke-width="0.5"
          class="text-base-content/20"
        />
        <text x="24" y="11" text-anchor="end" font-size="8" class="fill-base-content/60">
          {@max}
        </text>
        <text x="24" y="59" text-anchor="end" font-size="8" class="fill-base-content/60">
          {@min}
        </text>
        <path d={@area} fill="var(--color-primary)" fill-opacity="0.15" />
        <polyline
          points={@points}
          fill="none"
          stroke="var(--color-primary)"
          stroke-width="1.5"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
        <g>
          <rect
            :for={h <- @hovers}
            x={h.x - 5}
            y="8"
            width="10"
            height="48"
            fill="transparent"
            class="hover:fill-base-content/10"
          >
            <title>{h.date}: {h.value}</title>
          </rect>
        </g>
      </svg>
      <div class="flex justify-between text-[10px] text-base-content/50 tabular-nums">
        <span>{Calendar.strftime(@start_date, "%b %d")}</span>
        <span>last: {@last}</span>
        <span>{Calendar.strftime(@end_date, "%b %d")}</span>
      </div>
    </div>
    """
  end

  defp sparkline_paths([], _w, _h, _x0, _pad_y), do: {"", "", []}

  defp sparkline_paths(series, w, h, x_offset, pad_y) do
    max = Enum.max(series)
    min = Enum.min(series)
    range = max(max - min, 1)
    n = length(series)
    plot_w = w - x_offset
    plot_h = h - pad_y * 2
    step = if n > 1, do: plot_w / (n - 1), else: 0

    coords =
      series
      |> Enum.with_index()
      |> Enum.map(fn {v, i} ->
        x = x_offset + i * step
        y = h - pad_y - (v - min) / range * plot_h
        {Float.round(x, 2), Float.round(y, 2)}
      end)

    points =
      Enum.map_join(coords, " ", fn {x, y} -> "#{x},#{y}" end)

    [{x0, _} | _] = coords
    {xN, _} = List.last(coords)

    area =
      "M #{x0},#{h} " <>
        Enum.map_join(coords, " ", fn {x, y} -> "L #{x},#{y}" end) <>
        " L #{xN},#{h} Z"

    {points, area, coords}
  end
end
