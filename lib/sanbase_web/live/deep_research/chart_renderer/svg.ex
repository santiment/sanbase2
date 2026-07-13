defmodule SanbaseWeb.DeepResearch.ChartRenderer.Svg do
  @moduledoc """
  Server-side SVG implementation of `SanbaseWeb.DeepResearch.ChartRenderer`.

  Pure vector, rendered in Elixir — no JS hook, no browser, no extra deps, crisp
  at any size / in print, small payload (just the numbers). Supports:

    * `pie`  — a donut of category shares (e.g. messages by source).
    * `line` — a timeseries with optional shaded `spike` window and area fill
      (e.g. social volume/dominance with ~30d of before/after context).
  """
  use Phoenix.Component

  @behaviour SanbaseWeb.DeepResearch.ChartRenderer

  # Shared categorical palette (slices / series).
  @colors ~w(#6366f1 #10b981 #f59e0b #ef4444 #3b82f6 #ec4899 #14b8a6 #a855f7)

  @impl true
  def chart(assigns) do
    case assigns.spec[:type] do
      "pie" -> pie(assigns)
      type when type in ["line", "area", "spike"] -> line(assigns)
      _ -> blank(assigns)
    end
  end

  defp blank(assigns), do: ~H""

  # ── Pie (donut) ─────────────────────────────────────────────────────────
  # Uses the r=15.915 circle trick (circumference ≈ 100) so each slice's dash
  # length is its percentage; offset 25 starts the first slice at 12 o'clock.

  defp pie(assigns) do
    assigns = assign(assigns, :slices, pie_geometry(assigns.spec[:slices] || []))

    ~H"""
    <figure :if={@slices != []} class="rounded-xl border border-base-300 bg-base-100 p-4">
      <figcaption
        :if={@spec[:title]}
        class="mb-3 text-xs font-semibold uppercase tracking-wide text-base-content/60"
      >
        {@spec[:title]}
      </figcaption>
      <div class="flex flex-wrap items-center gap-x-6 gap-y-3">
        <svg viewBox="0 0 42 42" class="size-36 shrink-0" role="img">
          <circle cx="21" cy="21" r="15.915" fill="none" stroke="#e5e7eb" stroke-width="5" />
          <circle
            :for={s <- @slices}
            cx="21"
            cy="21"
            r="15.915"
            fill="none"
            stroke={s.color}
            stroke-width="5"
            stroke-dasharray={"#{s.dash} #{Float.round(100.0 - s.dash, 3)}"}
            stroke-dashoffset={s.offset}
          />
        </svg>
        <ul class="space-y-1.5 text-sm">
          <li :for={s <- @slices} class="flex items-center gap-2">
            <span class="inline-block size-3 shrink-0 rounded-sm" style={"background:#{s.color}"}>
            </span>
            <span class="text-base-content/80">{s.label}</span>
            <span class="text-base-content/50">{s.pct}%</span>
          </li>
        </ul>
      </div>
    </figure>
    """
  end

  defp pie_geometry(slices) do
    slices
    |> Enum.sort_by(& &1.value, :desc)
    |> cap_slices(7)
    |> pie_with_geometry()
  end

  defp cap_slices(slices, max) when length(slices) > max do
    {head, tail} = Enum.split(slices, max - 1)
    head ++ [%{label: "Other", value: tail |> Enum.map(& &1.value) |> Enum.sum()}]
  end

  defp cap_slices(slices, _max), do: slices

  defp pie_with_geometry(slices) do
    total = slices |> Enum.map(& &1.value) |> Enum.sum()

    if total <= 0 do
      []
    else
      {out, _cum} =
        slices
        |> Enum.with_index()
        |> Enum.map_reduce(0.0, fn {s, i}, cum ->
          pct = s.value / total * 100

          geom = %{
            label: s.label,
            pct: round(pct),
            dash: Float.round(pct, 3),
            offset: Float.round(25.0 - cum, 3),
            color: color_at(i)
          }

          {geom, cum + pct}
        end)

      out
    end
  end

  # ── Line / area (timeseries with optional spike band) ─────────────────────

  @vw 600
  @vh 200
  @pad 10

  defp line(assigns) do
    assigns = assign(assigns, :geo, line_geometry(assigns.spec))

    ~H"""
    <figure :if={@geo} class="rounded-xl border border-base-300 bg-base-100 p-4">
      <figcaption
        :if={@spec[:title]}
        class="mb-2 text-xs font-semibold uppercase tracking-wide text-base-content/60"
      >
        {@spec[:title]}
      </figcaption>
      <svg viewBox={"0 0 #{@geo.w} #{@geo.h}"} class="h-auto w-full" role="img">
        <rect
          :if={@geo.spike}
          x={@geo.spike.x}
          y="0"
          width={@geo.spike.w}
          height={@geo.h}
          fill="#f59e0b"
          fill-opacity="0.12"
        />
        <polygon :for={s <- @geo.series} points={s.area} fill={s.color} fill-opacity="0.08" />
        <polyline
          :for={s <- @geo.series}
          points={s.line}
          fill="none"
          stroke={s.color}
          stroke-width="1.5"
          stroke-linejoin="round"
          vector-effect="non-scaling-stroke"
        />
        <text x={@geo.w - 4} y="13" text-anchor="end" fill="#9ca3af" font-size="11">
          {@geo.vmax_label}
        </text>
      </svg>
      <div class="mt-1 flex justify-between text-[0.7rem] text-base-content/50">
        <span>{@geo.t_start}</span>
        <span :if={@geo.spike}>shaded = spike window</span>
        <span>{@geo.t_end}</span>
      </div>
      <ul :if={length(@geo.series) > 1} class="mt-2 flex flex-wrap gap-3 text-xs">
        <li :for={s <- @geo.series} class="flex items-center gap-1.5">
          <span class="inline-block size-2.5 rounded-sm" style={"background:#{s.color}"}></span>
          <span class="text-base-content/70">{s.label}</span>
        </li>
      </ul>
    </figure>
    """
  end

  defp line_geometry(spec) do
    series = spec[:series] || []
    pts = Enum.flat_map(series, & &1.points)

    if pts == [] do
      nil
    else
      ts = Enum.map(pts, & &1.t)
      vs = Enum.map(pts, & &1.v)
      {tmin, tmax} = {Enum.min(ts), Enum.max(ts)}
      {vmin, vmax} = {Enum.min(vs), Enum.max(vs)}
      base_y = @vh - @pad

      sx = fn t -> @pad + scale(t, tmin, tmax) * (@vw - 2 * @pad) end
      sy = fn v -> @pad + (1 - scale(v, vmin, vmax)) * (@vh - 2 * @pad) end

      geo_series =
        series
        |> Enum.with_index()
        |> Enum.map(fn {s, i} ->
          line = Enum.map_join(s.points, " ", fn p -> "#{r(sx.(p.t))},#{r(sy.(p.v))}" end)
          fx = sx.(List.first(s.points).t)
          lx = sx.(List.last(s.points).t)
          area = "#{r(fx)},#{r(base_y)} #{line} #{r(lx)},#{r(base_y)}"
          %{label: s.label, line: line, area: area, color: color_at(i)}
        end)

      %{
        w: @vw,
        h: @vh,
        series: geo_series,
        spike: spike_band(spec[:spike], sx, tmin, tmax),
        vmax_label: fmt_num(vmax),
        t_start: fmt_date(tmin),
        t_end: fmt_date(tmax)
      }
    end
  end

  defp spike_band(%{from: f, to: t}, sx, tmin, tmax) do
    x1 = sx.(clamp(f, tmin, tmax))
    x2 = sx.(clamp(t, tmin, tmax))
    %{x: r(min(x1, x2)), w: r(abs(x2 - x1))}
  end

  defp spike_band(_spike, _sx, _tmin, _tmax), do: nil

  # ── Shared helpers ────────────────────────────────────────────────────────

  defp color_at(i), do: Enum.at(@colors, rem(i, length(@colors)))

  defp scale(x, lo, hi) when hi > lo, do: (x - lo) / (hi - lo)
  defp scale(_x, _lo, _hi), do: 0.5

  defp clamp(x, lo, hi), do: x |> max(lo) |> min(hi)

  defp r(f), do: Float.round(f * 1.0, 1)

  defp fmt_num(n) when is_number(n) do
    a = abs(n)

    cond do
      a >= 1.0e9 -> "#{Float.round(n / 1.0e9, 1)}B"
      a >= 1.0e6 -> "#{Float.round(n / 1.0e6, 1)}M"
      a >= 1.0e3 -> "#{Float.round(n / 1.0e3, 1)}k"
      a >= 1 -> "#{round(n)}"
      true -> "#{Float.round(n * 1.0, 2)}"
    end
  end

  defp fmt_date(t) when is_number(t) do
    case DateTime.from_unix(trunc(t)) do
      {:ok, dt} -> Calendar.strftime(dt, "%b %d")
      _ -> ""
    end
  end
end
