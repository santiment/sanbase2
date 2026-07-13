defmodule SanbaseWeb.DeepResearch.ChartRenderer do
  @moduledoc """
  Renders a normalized in-report chart spec (produced by
  `Sanbase.DeepResearch.Timeline.split_charts/1`) to safe HTML embedded in the
  research report.

  The spec is **renderer-agnostic data** — parsing/validation lives in the
  Timeline, the visual lives here — so a different backend (e.g. a JS
  lightweight-charts → `takeScreenshot()` PNG) can consume the exact same spec:

    * `%{type: "pie",  title: t, slices: [%{label, value}]}`
    * `%{type: "line", title: t, series: [%{label, points: [%{t, v}]}], spike: %{from, to} | nil}`

  ## Swapping the backend

  The default is the server-side SVG renderer (`#{inspect(__MODULE__)}.Svg`) —
  no JS, no browser, crisp vector. To swap (e.g. to a future PNG renderer),
  point the config at another module implementing this behaviour:

      config :sanbase, :dra_chart_renderer, SanbaseWeb.DeepResearch.ChartRenderer.Png

  Every implementation is a `Phoenix.Component` exposing `chart/1`.
  """

  @callback chart(assigns :: %{required(:spec) => map()}) :: Phoenix.LiveView.Rendered.t()

  @doc "The configured renderer module (defaults to the server-side SVG one)."
  @spec impl() :: module()
  def impl, do: Application.get_env(:sanbase, :dra_chart_renderer, __MODULE__.Svg)

  @doc "Render a normalized chart `spec` with the configured renderer."
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(spec), do: impl().chart(%{spec: spec})
end
