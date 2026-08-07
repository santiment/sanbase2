defmodule SanbaseWeb.DeepResearch.ChartRenderer do
  @moduledoc """
  Renders a normalized in-report chart spec (produced by
  `Sanbase.DeepResearch.ReportMarkdown.split_charts/1`) to safe HTML embedded in
  the research report.

  > #### Not the only chart path {: .info}
  >
  > The agent draws charts two ways, on purpose, and they do **not** share a spec:
  >
  >   * **In-report** (this module) — a fenced ` ```chart ` block in the final
  >     markdown, parsed into the atom-keyed spec below and rendered server-side
  >     as static SVG. Printable, no JS, survives a page reload.
  >   * **Live timeline** — a `chart` event on the custom stream channel, passed
  >     through to the `LightweightChart` JS hook as string-keyed JSON
  >     (`%{"label" => …}`) for an interactive lightweight-charts widget.
  >
  > Changing one does not change the other; a spec field added here needs its own
  > counterpart in `assets/js/hooks/lightweight_chart.js`.

  The spec is **renderer-agnostic data** — parsing/validation lives in
  `Sanbase.DeepResearch.ReportMarkdown.split_charts/1`, the visual lives here —
  so a different backend (e.g. a JS
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
  def impl(), do: Application.get_env(:sanbase, :dra_chart_renderer, __MODULE__.Svg)

  @doc "Render a normalized chart `spec` with the configured renderer."
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(spec) do
    # The renderer module is chosen at runtime, so it is invoked by hand rather
    # than through `<.component />`. A hand-built assigns map MUST carry
    # `__changed__` or `Phoenix.Component.assign/3` inside the renderer raises;
    # `nil` means "treat everything as changed", i.e. always render in full.
    # That is correct here: a report chart is static once the report is written.
    impl().chart(%{spec: spec, __changed__: nil})
  end
end
