defmodule SanbaseWeb.Admin.TimeseriesChart do
  @moduledoc """
  Reusable Grafana-style multi-series time chart for admin LiveViews.

  Rendering is done client-side by the `TimeseriesChart` JS hook
  (`assets/js/hooks/timeseries_chart.js`, built on lightweight-charts):
  crosshair, a legend that doubles as the value readout on hover, a
  colorblind-safe categorical palette validated for both admin themes, and
  an explicit empty state. A series keeps its color for the lifetime of the
  page even as other series come and go; at most 8 series are drawn and the
  legend notes any overflow.

  ## Usage

  Render a chart container (a static placeholder the hook owns):

      import SanbaseWeb.Admin.TimeseriesChart

      ~H\"\"\"
      <.timeseries_chart id="my-chart" height="320px" />
      \"\"\"

  Then push data to it from `mount`/`handle_params`/`handle_event`/
  `handle_info` — every push fully replaces the chart contents:

      socket =
        TimeseriesChart.push_data(socket, "my-chart", series, value_kind: :bytes)

  **Required**: the LiveView must also handle the hook's ready handshake by
  re-pushing the chart data (data pushed during mount can be dispatched
  before the hook is listening and silently dropped):

      def handle_event("chart-ready", %{"id" => _id}, socket) do
        {:noreply, push_my_chart_data(socket)}
      end

  where `series` is a list of `%{name: String.t(), points: [[unix_seconds, number]]}`
  (points oldest-first; build them server-side, see
  `Sanbase.Monitoring.MemoryStat.multi_pod_metric_series/4` for an example).

  `value_kind` picks the axis/legend formatter: `:bytes` (KB/MB/GB),
  `:count` (thousands separators) or `:percent`.
  """

  use Phoenix.Component

  @value_kinds [:bytes, :count, :percent]

  attr(:id, :string, required: true, doc: "unique DOM id; also the push_data/4 target")
  attr(:height, :string, default: "320px")

  def timeseries_chart(assigns) do
    ~H"""
    <div id={@id} phx-hook="TimeseriesChart" phx-update="ignore" data-height={@height}></div>
    """
  end

  @doc """
  Push `series` to the chart with DOM id `id`. Replaces the chart contents.

  Options: `:value_kind` — one of #{inspect(@value_kinds)}, default `:count`.
  """
  def push_data(socket, id, series, opts \\ []) when is_list(series) do
    value_kind = Keyword.get(opts, :value_kind, :count)

    unless value_kind in @value_kinds do
      raise ArgumentError,
            "invalid value_kind #{inspect(value_kind)}, expected one of #{inspect(@value_kinds)}"
    end

    Phoenix.LiveView.push_event(socket, "chart-data-#{id}", %{
      series: series,
      value_kind: Atom.to_string(value_kind)
    })
  end
end
