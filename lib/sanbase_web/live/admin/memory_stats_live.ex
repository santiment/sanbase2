defmodule SanbaseWeb.Admin.MemoryStatsLive do
  @moduledoc """
  Read-only admin dashboard over `Sanbase.Monitoring.MemoryStat` rows written
  every minute by each pod's `Sanbase.Monitoring.MemoryCollector`.

  Shows the pods that reported recently (Deployment pods change names on
  every rollout, so only live pods are listed), and per pod: latest numbers,
  the change over the current BEAM incarnation (a restart resets memory, so
  diffing across one is meaningless), top ETS tables / process groups, and
  the recent raw samples. Auto-refreshes every minute.
  """
  use SanbaseWeb, :live_view

  import SanbaseWeb.GenericAdminHTML, only: [stat_card: 1]
  import SanbaseWeb.Admin.TimeseriesChart, only: [timeseries_chart: 1]

  alias Sanbase.Monitoring.MemoryCollector
  alias Sanbase.Monitoring.MemoryStat
  alias SanbaseWeb.Admin.TimeseriesChart

  @live_window_minutes 5
  @series_hours 24
  @samples_shown 20
  @refresh_interval 60_000

  @chart_metric_options [
    {"OS RSS", "rss_bytes"},
    {"RSS high-water", "rss_hwm_bytes"},
    {"VM total", "vm_total_bytes"},
    {"VM processes", "vm_processes_bytes"},
    {"VM binary", "vm_binary_bytes"},
    {"VM ETS", "vm_ets_bytes"},
    {"Process count", "process_count"}
  ]

  @pod_chart_modes [
    {"Buckets", "buckets"},
    {"Layers (leak vs ratchet)", "layers"},
    {"Alloc utilization %", "util"}
  ]

  @chart_window_options [
    {"1h", 1},
    {"6h", 6},
    {"24h", 24},
    {"3d", 72},
    {"7d", 168}
  ]

  # {label, MemoryStat row field} pairs, one list per per-pod chart mode.
  # "Which bucket of live data grows?"
  @pod_bucket_series [
    {"OS RSS", :rss_bytes},
    {"VM total", :vm_total_bytes},
    {"VM processes", :vm_processes_bytes},
    {"VM binary", :vm_binary_bytes},
    {"VM ETS", :vm_ets_bytes}
  ]

  # The three accounting layers plus the RSS high-water mark. The gaps name the cause of
  # RSS growth: allocated − used = carrier slack (spike ratchet or fragmentation, not a
  # leak), RSS − allocated = native/NIF memory invisible to the VM, and RSS converging
  # toward a flat early high-water = a past spike.
  @pod_layer_series [
    {"RSS high-water", :rss_hwm_bytes},
    {"OS RSS", :rss_bytes},
    {"Alloc allocated (carriers)", :alloc_allocated_bytes},
    {"Alloc used (blocks)", :alloc_used_bytes},
    {"VM total", :vm_total_bytes}
  ]

  # includes two derived components computed per sample in incarnation_stats/2:
  # carrier slack (allocated − used) and native/other (RSS − allocated)
  @stat_metrics [
    {:rss_bytes, "OS RSS", :bytes},
    {:rss_hwm_bytes, "RSS high-water", :bytes},
    {:vm_total_bytes, "VM total", :bytes},
    {:vm_processes_bytes, "VM processes", :bytes},
    {:vm_binary_bytes, "VM binary", :bytes},
    {:vm_ets_bytes, "VM ETS", :bytes},
    {:vm_code_bytes, "VM code", :bytes},
    {:alloc_used_bytes, "Alloc used (blocks)", :bytes},
    {:alloc_allocated_bytes, "Alloc allocated (carriers)", :bytes},
    {:carrier_slack_bytes, "Carrier slack (allocated − used)", :bytes},
    {:native_other_bytes, "Native/other (RSS − allocated)", :bytes},
    {:process_count, "Process count", :count},
    {:atom_count, "Atom count", :count}
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_interval, self(), :refresh)

    {:ok,
     assign(socket,
       page_title: "Memory Stats",
       live_window_minutes: @live_window_minutes,
       series_hours: @series_hours,
       samples_shown: @samples_shown,
       # nil = auto: RSS when available, else VM total (RSS needs /proc, so
       # it is absent on macOS dev). Becomes a list once the user toggles one.
       chart_metrics: nil,
       chart_hours: 24,
       chart_metric_options: @chart_metric_options,
       chart_window_options: @chart_window_options,
       pod_chart_mode: "buckets",
       pod_chart_modes: @pod_chart_modes,
       collector_enabled: MemoryCollector.enabled?()
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:selected_pod, params["pod"])
     |> load_data()}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("toggle-metric", %{"metric" => metric}, socket) do
    if Enum.any?(@chart_metric_options, fn {_label, m} -> m == metric end) do
      current = socket.assigns.chart_metrics_effective

      new_metrics =
        cond do
          # never deselect the last remaining metric
          metric in current and length(current) == 1 -> current
          metric in current -> current -- [metric]
          # counts cannot share an axis with bytes — process_count is exclusive
          metric == "process_count" -> [metric]
          true -> [metric | current -- ["process_count"]]
        end
        |> normalize_metric_order()

      {:noreply,
       socket
       |> assign(:chart_metrics, new_metrics)
       |> refresh_charts()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("chart-window", %{"hours" => hours}, socket) do
    hours =
      case Enum.find(@chart_window_options, fn {_label, h} -> to_string(h) == hours end) do
        {_label, h} -> h
        nil -> 24
      end

    {:noreply,
     socket
     |> assign(:chart_hours, hours)
     |> refresh_charts()}
  end

  # Sent by the TimeseriesChart hook once it is mounted and listening —
  # data pushed before that (from mount/handle_params) may be dropped.
  @impl true
  def handle_event("chart-ready", %{"id" => _id}, socket) do
    {:noreply, push_chart_events(socket)}
  end

  @impl true
  def handle_event("pod-chart-mode", %{"mode" => mode}, socket) do
    mode =
      if Enum.any?(@pod_chart_modes, fn {_label, m} -> m == mode end),
        do: mode,
        else: "buckets"

    {:noreply,
     socket
     |> assign(:pod_chart_mode, mode)
     |> refresh_charts()}
  end

  defp load_data(socket) do
    pods = MemoryStat.latest_per_pod(@live_window_minutes)

    socket
    |> assign(pods: pods, known_pods: known_pods_not_live(pods))
    |> assign_effective_metrics()
    |> assign_selected()
    |> push_chart_events()
  end

  # Only the chart payload depends on the metric/window/mode badges, not the pod tables or
  # the details below them, so reloading everything on a badge click would re-run the
  # cross-pod aggregates for nothing. The selected pod's rows are re-read because a wider
  # window needs more of them.
  defp refresh_charts(socket) do
    socket
    |> assign_effective_metrics()
    |> assign_pod_rows()
    |> push_chart_events()
  end

  defp known_pods_not_live(pods) do
    live_names = MapSet.new(pods, & &1.pod_name)

    MemoryStat.known_pods()
    |> Enum.reject(&MapSet.member?(live_names, &1.pod_name))
  end

  defp assign_effective_metrics(socket) do
    assign(
      socket,
      :chart_metrics_effective,
      effective_metrics(socket.assigns.chart_metrics, socket.assigns.pods)
    )
  end

  # RSS is the primary prod metric but needs /proc; when no live pod reports
  # it (macOS dev), auto-default to VM total instead of showing a blank chart
  defp effective_metrics(nil, pods) do
    if pods != [] and Enum.all?(pods, &is_nil(&1.rss_bytes)),
      do: ["vm_total_bytes"],
      else: ["rss_bytes"]
  end

  defp effective_metrics(metrics, _pods), do: metrics

  # A pod missing from the live list may still have recorded history
  # (Deployment pods get replaced on every rollout) — show it, with a
  # staleness warning on top, until the rows are pruned.
  defp assign_selected(socket) do
    %{pods: pods, selected_pod: selected_pod} = socket.assigns

    {latest, stale?} =
      case Enum.find(pods, &(&1.pod_name == selected_pod)) do
        nil when is_binary(selected_pod) -> {MemoryStat.latest_for_pod(selected_pod), true}
        live -> {live, false}
      end

    details_stat = if latest, do: MemoryStat.latest_details(selected_pod)

    socket
    |> assign(selected: latest, selected_stale: latest != nil and stale?)
    |> assign(details_stat: details_stat)
    |> assign_pod_rows()
  end

  # One fetch feeds both the per-pod chart and everything below it - the rows are read once
  # over the widest window in play, then sliced. `series` stays the fixed @series_hours
  # window that the samples table and the window stats describe.
  defp assign_pod_rows(socket) do
    case socket.assigns.selected do
      nil ->
        assign(socket, pod_rows: [], series: [], window_stats: nil)

      selected ->
        hours = max(@series_hours, socket.assigns.chart_hours)
        rows = MemoryStat.pod_series(selected.pod_name, hours)
        series = within_hours(rows, @series_hours)

        assign(socket,
          pod_rows: rows,
          series: series,
          window_stats: incarnation_stats(series, selected)
        )
    end
  end

  defp within_hours(rows, hours) do
    cutoff = NaiveDateTime.utc_now() |> NaiveDateTime.add(-hours * 3600, :second)

    Enum.filter(rows, &(NaiveDateTime.compare(&1.inserted_at, cutoff) == :gt))
  end

  defp push_chart_events(socket) do
    socket
    |> push_overview_chart()
    |> push_pod_chart()
  end

  defp push_overview_chart(%{assigns: %{pods: []}} = socket), do: socket

  defp push_overview_chart(socket) do
    %{pods: pods, chart_metrics_effective: metrics, chart_hours: hours} = socket.assigns
    pod_names = Enum.map(pods, & &1.pod_name)

    series =
      Enum.flat_map(metrics, fn metric ->
        MemoryStat.multi_pod_metric_series(pod_names, chart_metric_atom(metric), hours)
        |> Enum.map(fn s -> %{s | name: series_name(s.name, metric, metrics)} end)
      end)

    TimeseriesChart.push_data(socket, "overview-chart", series,
      value_kind: overview_value_kind(metrics)
    )
  end

  defp push_pod_chart(%{assigns: %{selected: nil}} = socket), do: socket

  defp push_pod_chart(socket) do
    %{pod_rows: rows, pod_chart_mode: mode, chart_hours: hours} = socket.assigns
    {series, kind} = pod_chart_series(mode, within_hours(rows, hours))

    TimeseriesChart.push_data(socket, "pod-chart", series, value_kind: kind)
  end

  defp pod_chart_series("layers", rows),
    do: {MemoryStat.labeled_series(rows, @pod_layer_series), :bytes}

  defp pod_chart_series("util", rows),
    do:
      {MemoryStat.labeled_series(rows, [{"Allocator utilization", &MemoryStat.utilization/1}]),
       :percent}

  defp pod_chart_series(_buckets, rows),
    do: {MemoryStat.labeled_series(rows, @pod_bucket_series), :bytes}

  # keep the option order so series order and colors stay stable
  defp normalize_metric_order(metrics) do
    for {_label, value} <- @chart_metric_options, value in metrics, do: value
  end

  defp chart_metric_atom(metric_string) do
    Enum.find(MemoryStat.chart_metrics(), :rss_bytes, &(Atom.to_string(&1) == metric_string))
  end

  # one metric -> series named by pod; several -> "pod · metric"
  defp series_name(pod_name, _metric, [_single]), do: pod_name

  defp series_name(pod_name, metric, _metrics),
    do: "#{pod_name} · #{chart_metric_label(metric)}"

  defp overview_value_kind(["process_count"]), do: :count
  defp overview_value_kind(_metrics), do: :bytes

  # Per-metric stats over the CURRENT BEAM incarnation only - a restart resets memory, so
  # mixing incarnations is meaningless. Point-in-time diffs are traffic noise, so the trend
  # column compares the average of the first 10% of samples with the average of the last
  # 10%, smoothing out load swings to answer "is it actually growing".
  defp incarnation_stats(series, latest) do
    same =
      series
      |> Enum.filter(&(&1.beam_started_at == latest.beam_started_at))
      |> Enum.map(&Map.merge(&1, derived_components(&1)))

    if length(same) >= 10 do
      %{
        from: List.first(same).inserted_at,
        to: List.last(same).inserted_at,
        edge_count: edge_count(length(same)),
        rows:
          for(
            {key, label, kind} <- @stat_metrics,
            values = for(row <- same, v = Map.get(row, key), is_integer(v), do: v),
            length(values) >= 2,
            do: metric_row(label, kind, values)
          )
      }
    end
  end

  defp metric_row(label, kind, values) do
    # sized against this metric's own samples: the alloc-derived ones are nil
    # whenever allocator stats were unavailable, and a window sized for the
    # full series would overlap itself and zero the trend
    edge = edge_count(length(values))
    start_avg = avg(Enum.take(values, edge))
    now_avg = avg(Enum.take(values, -edge))
    {min_value, max_value} = Sanbase.Math.min_max(values)

    %{
      label: label,
      kind: kind,
      min: min_value,
      avg: avg(values),
      max: max_value,
      start_avg: start_avg,
      now_avg: now_avg,
      delta: now_avg - start_avg
    }
  end

  # 10% of the samples at each end, at least 5, and never more than half so
  # the two windows cannot overlap
  defp edge_count(count) do
    count |> div(10) |> max(5) |> min(div(count, 2))
  end

  defp avg(values), do: div(Enum.sum(values), length(values))

  # Where does RSS growth actually live? Carrier slack = allocator carriers
  # not filled with live data (ratchet/fragmentation); native/other = memory
  # the VM's own accounting cannot see (NIFs, OpenSSL, code mappings).
  defp derived_components(row) do
    %{
      carrier_slack_bytes: alloc_unused(row),
      native_other_bytes: safe_sub(row.rss_bytes, row.alloc_allocated_bytes)
    }
  end

  defp safe_sub(a, b) when is_integer(a) and is_integer(b), do: a - b
  defp safe_sub(_, _), do: nil

  defp pod_chart_mode_label(mode) do
    {label, _} = List.keyfind(@pod_chart_modes, mode, 1, {"Buckets", "buckets"})
    label
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-baseline justify-between">
        <h1 class="text-xl font-semibold">Memory Stats</h1>
        <p class="text-sm text-base-content/60">
          Sampled every minute by each pod · auto-refreshes every minute
        </p>
      </div>

      <div :if={!@collector_enabled} id="collector-disabled-warning" class="alert alert-warning">
        <span>
          Memory collection is off on this pod — no new samples are being recorded. Set
          <code class="font-mono font-semibold">MEMORY_COLLECTOR_ENABLED=true</code>
          and restart to enable it. Anything below is history kept from before it was turned off.
        </span>
      </div>

      <section id="live-pods">
        <.section_heading>
          Live pods (reported in the last {@live_window_minutes} min)
        </.section_heading>
        <div class="overflow-x-auto bg-base-100 border border-base-300 rounded">
          <table class="table table-sm">
            <thead>
              <tr class="text-base-content/60">
                <th>Pod</th>
                <th>Type</th>
                <th class="text-right">Uptime</th>
                <th class="text-right">RSS</th>
                <th class="text-right">VM total</th>
                <th class="text-right">Processes</th>
                <th class="text-right">Binary</th>
                <th class="text-right">ETS</th>
                <th class="text-right">Proc #</th>
                <th class="text-right">Alloc unused</th>
                <th class="text-right">Sample ms</th>
                <th class="text-right">Age</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={pod <- @pods}
                id={"live-pod-#{pod.pod_name}"}
                class={[
                  "hover:bg-base-200",
                  @selected_pod == pod.pod_name && "bg-base-200 font-medium"
                ]}
              >
                <td>
                  <.link patch={~p"/admin/memory_stats?pod=#{pod.pod_name}"} class="link">
                    {pod.pod_name}
                  </.link>
                </td>
                <td>{pod.container_type}</td>
                <td class="text-right tabular-nums">{uptime(pod.beam_started_at)}</td>
                <td class="text-right tabular-nums">{fmt_bytes(pod.rss_bytes)}</td>
                <td class="text-right tabular-nums">{fmt_bytes(pod.vm_total_bytes)}</td>
                <td class="text-right tabular-nums">{fmt_bytes(pod.vm_processes_bytes)}</td>
                <td class="text-right tabular-nums">{fmt_bytes(pod.vm_binary_bytes)}</td>
                <td class="text-right tabular-nums">{fmt_bytes(pod.vm_ets_bytes)}</td>
                <td class="text-right tabular-nums">{pod.process_count}</td>
                <td class="text-right tabular-nums">{fmt_bytes(alloc_unused(pod))}</td>
                <td class="text-right tabular-nums">{pod.sample_duration_ms}</td>
                <td class="text-right tabular-nums">{age(pod.inserted_at)}</td>
              </tr>
              <tr :if={@pods == []} id="no-pods">
                <td colspan="12" class="text-center text-base-content/50">
                  No pods reported recently. Is Sanbase.Monitoring.MemoryCollector enabled?
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section :if={@known_pods != []} id="known-pods">
        <.section_heading>
          Known pods, not reporting now (history kept until pruned)
        </.section_heading>
        <div class="overflow-x-auto bg-base-100 border border-base-300 rounded">
          <table class="table table-sm">
            <thead>
              <tr class="text-base-content/60">
                <th>Pod</th>
                <th>Type</th>
                <th class="text-right">Oldest snapshot (UTC)</th>
                <th class="text-right">Last snapshot (UTC)</th>
                <th class="text-right">Last seen</th>
                <th class="text-right">Samples</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={pod <- @known_pods}
                id={"known-pod-#{pod.pod_name}"}
                class="hover:bg-base-200"
              >
                <td>
                  <.link patch={~p"/admin/memory_stats?pod=#{pod.pod_name}"} class="link">
                    {pod.pod_name}
                  </.link>
                </td>
                <td>{pod.container_type}</td>
                <td class="text-right tabular-nums">{fmt_time(pod.first_seen)}</td>
                <td class="text-right tabular-nums">{fmt_time(pod.last_seen)}</td>
                <td class="text-right tabular-nums">{age(pod.last_seen)} ago</td>
                <td class="text-right tabular-nums">{pod.samples}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section :if={@pods != []} id="overview-chart-section">
        <div class="flex flex-col items-start mb-2 gap-2">
          <h2
            id="overview-chart-title"
            class="text-sm font-semibold uppercase tracking-wide text-base-content/60"
          >
            {chart_metrics_label(@chart_metrics_effective)} · all live pods · last {chart_window_label(
              @chart_hours
            )}
          </h2>
          <div class="flex flex-wrap items-center gap-1">
            <.toggle_badge
              :for={{label, value} <- @chart_metric_options}
              label={label}
              selected={value in @chart_metrics_effective}
              click="toggle-metric"
              value_name="metric"
              value={value}
            />
            <span class="mx-1 text-base-content/30">·</span>
            <.toggle_badge
              :for={{label, value} <- @chart_window_options}
              label={label}
              selected={value == @chart_hours}
              click="chart-window"
              value_name="hours"
              value={value}
            />
          </div>
        </div>
        <div class="bg-base-100 border border-base-300 rounded p-3">
          <.timeseries_chart id="overview-chart" height="320px" />
        </div>
        <p class="text-xs text-base-content/50 mt-1">
          Click badges to combine byte metrics on one chart; process count plots alone
          (different unit, one axis).
        </p>
      </section>

      <div
        :if={@selected_pod && is_nil(@selected)}
        id="no-samples-warning"
        class="alert alert-warning"
      >
        No samples recorded for pod {@selected_pod}.
      </div>

      <div :if={@selected && @selected_stale} id="stale-pod-warning" class="alert alert-warning">
        Pod {@selected.pod_name} has not reported in the last {@live_window_minutes} minutes —
        it was likely replaced by a newer deployment or stopped. Last sample {age(
          @selected.inserted_at
        )} ago; showing its recorded history below.
      </div>

      <div :if={@selected} class="space-y-4">
        <section id="latest-sample">
          <.section_heading>{@selected.pod_name} · latest sample</.section_heading>
          <div class="grid gap-2 grid-cols-2 sm:grid-cols-4 lg:grid-cols-8">
            <.stat_card label="OS RSS" value={fmt_bytes(@selected.rss_bytes)} />
            <.stat_card label="VM total" value={fmt_bytes(@selected.vm_total_bytes)} />
            <.stat_card label="Processes mem" value={fmt_bytes(@selected.vm_processes_bytes)} />
            <.stat_card label="Binary" value={fmt_bytes(@selected.vm_binary_bytes)} />
            <.stat_card label="ETS" value={fmt_bytes(@selected.vm_ets_bytes)} />
            <.stat_card label="Process count" value={@selected.process_count} />
            <.stat_card label="Atoms" value={@selected.atom_count} />
            <.stat_card
              label="Uptime"
              value={uptime(@selected.beam_started_at, @selected.inserted_at)}
            />
          </div>
        </section>

        <section id="pod-chart-section">
          <div class="flex flex-col items-start mb-2 gap-2">
            <h2
              id="pod-chart-title"
              class="text-sm font-semibold uppercase tracking-wide text-base-content/60"
            >
              {@selected.pod_name} · {pod_chart_mode_label(@pod_chart_mode)} · last {chart_window_label(
                @chart_hours
              )}
            </h2>
            <div class="flex flex-wrap items-center gap-1">
              <.toggle_badge
                :for={{label, value} <- @pod_chart_modes}
                label={label}
                selected={value == @pod_chart_mode}
                click="pod-chart-mode"
                value_name="mode"
                value={value}
              />
            </div>
          </div>
          <div class="bg-base-100 border border-base-300 rounded p-3">
            <.timeseries_chart id="pod-chart" height="280px" />
          </div>
          <p :if={@pod_chart_mode == "layers"} class="text-xs text-base-content/50 mt-1">
            Reading the gaps: allocated − used = carrier slack (spike ratchet / fragmentation —
            not a leak); RSS − allocated = native/NIF memory the VM cannot see; RSS converging
            toward a flat early high-water = a past spike set the level. Only growth in
            "used"/"VM total" is live data your code holds.
          </p>
          <p :if={@pod_chart_mode == "util"} class="text-xs text-base-content/50 mt-1">
            Falling utilization while RSS rises = fragmentation or carrier ratchet.
            Stable high utilization = memory holds real data — check the Buckets view.
          </p>
        </section>

        <section :if={@window_stats} id="window-stats">
          <.section_heading>
            Window stats, current incarnation
            ({fmt_time(@window_stats.from)} → {fmt_time(@window_stats.to)} UTC)
          </.section_heading>
          <div class="overflow-x-auto bg-base-100 border border-base-300 rounded">
            <table class="table table-sm">
              <thead>
                <tr class="text-base-content/60">
                  <th>Metric</th>
                  <th class="text-right">Min</th>
                  <th class="text-right">Avg</th>
                  <th class="text-right">Max</th>
                  <th class="text-right">Start avg</th>
                  <th class="text-right">Now avg</th>
                  <th class="text-right">Trend</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @window_stats.rows} class="hover:bg-base-200">
                  <td class="font-medium">{row.label}</td>
                  <td class="text-right tabular-nums">{fmt_metric(row.min, row.kind)}</td>
                  <td class="text-right tabular-nums">{fmt_metric(row.avg, row.kind)}</td>
                  <td class="text-right tabular-nums">{fmt_metric(row.max, row.kind)}</td>
                  <td class="text-right tabular-nums">{fmt_metric(row.start_avg, row.kind)}</td>
                  <td class="text-right tabular-nums">{fmt_metric(row.now_avg, row.kind)}</td>
                  <td class={["text-right tabular-nums", delta_class(row.delta)]}>
                    {fmt_delta(row.delta, row.kind)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p class="text-xs text-base-content/50 mt-1">
            Trend = average of the last ~{@window_stats.edge_count} samples minus average of the
            first ~{@window_stats.edge_count} — smooths out per-minute traffic swings; a steadily
            positive trend across refreshes is the leak signal, not any single diff. Metrics that
            were not recorded on every sample use a proportionally smaller window.
          </p>
        </section>

        <div :if={details(@details_stat) != %{}} class="grid grid-cols-1 lg:grid-cols-2 gap-3">
          <section :if={details(@details_stat)["top_ets"]} id="top-ets">
            <.section_heading>
              Top ETS tables ({fmt_time(@details_stat.inserted_at)} UTC)
            </.section_heading>
            <div class="overflow-x-auto bg-base-100 border border-base-300 rounded">
              <table class="table table-sm">
                <thead>
                  <tr class="text-base-content/60">
                    <th>Table</th>
                    <th class="text-right">Memory</th>
                    <th class="text-right">Rows</th>
                    <th>Owner</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={row <- details(@details_stat)["top_ets"]} class="hover:bg-base-200">
                    <td class="font-medium break-all">{row["name"]}</td>
                    <td class="text-right tabular-nums">{fmt_bytes(row["memory_bytes"])}</td>
                    <td class="text-right tabular-nums">{row["rows"]}</td>
                    <td class="break-all">{row["owner"]}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>

          <section :if={details(@details_stat)["process_groups"]} id="process-groups">
            <.section_heading>
              Top process groups ({fmt_time(@details_stat.inserted_at)} UTC)
            </.section_heading>
            <div class="overflow-x-auto bg-base-100 border border-base-300 rounded">
              <table class="table table-sm">
                <thead>
                  <tr class="text-base-content/60">
                    <th>Name</th>
                    <th class="text-right">Count</th>
                    <th class="text-right">Memory</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={row <- details(@details_stat)["process_groups"]}
                    class="hover:bg-base-200"
                  >
                    <td class="font-medium break-all">{row["name"]}</td>
                    <td class="text-right tabular-nums">{row["count"]}</td>
                    <td class="text-right tabular-nums">{fmt_bytes(row["memory_bytes"])}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>
        </div>

        <section id="recent-samples">
          <.section_heading>
            Recent samples (last {min(length(@series), @samples_shown)} of {length(@series)} in {@series_hours}h,
            newest first)
          </.section_heading>
          <div class="overflow-x-auto bg-base-100 border border-base-300 rounded max-h-96 overflow-y-auto">
            <table class="table table-sm">
              <thead>
                <tr class="text-base-content/60">
                  <th>Time (UTC)</th>
                  <th class="text-right">RSS</th>
                  <th class="text-right">VM total</th>
                  <th class="text-right">Processes</th>
                  <th class="text-right">Binary</th>
                  <th class="text-right">ETS</th>
                  <th class="text-right">Alloc unused</th>
                  <th class="text-right">Proc #</th>
                  <th class="text-right">Atoms</th>
                  <th class="text-right">Sample ms</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={row <- @series |> Enum.reverse() |> Enum.take(@samples_shown)}
                  class="hover:bg-base-200"
                >
                  <td class="tabular-nums">{fmt_time(row.inserted_at)}</td>
                  <td class="text-right tabular-nums">{fmt_bytes(row.rss_bytes)}</td>
                  <td class="text-right tabular-nums">{fmt_bytes(row.vm_total_bytes)}</td>
                  <td class="text-right tabular-nums">{fmt_bytes(row.vm_processes_bytes)}</td>
                  <td class="text-right tabular-nums">{fmt_bytes(row.vm_binary_bytes)}</td>
                  <td class="text-right tabular-nums">{fmt_bytes(row.vm_ets_bytes)}</td>
                  <td class="text-right tabular-nums">{fmt_bytes(alloc_unused(row))}</td>
                  <td class="text-right tabular-nums">{row.process_count}</td>
                  <td class="text-right tabular-nums">{row.atom_count}</td>
                  <td class="text-right tabular-nums">{row.sample_duration_ms}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </div>
    """
  end

  attr(:label, :string, required: true)
  attr(:selected, :boolean, required: true)
  attr(:click, :string, required: true)
  attr(:value_name, :string, required: true)
  attr(:value, :any, required: true)

  defp toggle_badge(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@click}
      {%{"phx-value-#{@value_name}" => @value}}
      class={[
        "badge badge-lg cursor-pointer select-none",
        (@selected && "badge-primary") || "badge-outline text-base-content/70"
      ]}
    >
      {@label}
    </button>
    """
  end

  slot(:inner_block, required: true)

  defp section_heading(assigns) do
    ~H"""
    <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60 mb-2">
      {render_slot(@inner_block)}
    </h2>
    """
  end

  defp details(nil), do: %{}
  defp details(stat), do: stat.details || %{}

  defp chart_metric_label(metric) do
    {label, _} = List.keyfind(@chart_metric_options, metric, 1, {"OS RSS", "rss_bytes"})
    label
  end

  defp chart_metrics_label(metrics) do
    metrics |> Enum.map(&chart_metric_label/1) |> Enum.join(" + ")
  end

  defp chart_window_label(hours) do
    {label, _} = List.keyfind(@chart_window_options, hours, 1, {"24h", 24})
    label
  end

  defp alloc_unused(row), do: safe_sub(row.alloc_allocated_bytes, row.alloc_used_bytes)

  defp fmt_bytes(nil), do: "—"

  defp fmt_bytes(bytes) when is_integer(bytes) do
    cond do
      abs(bytes) >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 2)} GB"
      abs(bytes) >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 1)} MB"
      true -> "#{Float.round(bytes / 1024, 1)} KB"
    end
  end

  defp fmt_metric(value, :bytes), do: fmt_bytes(value)
  defp fmt_metric(value, :count), do: value

  defp fmt_delta(delta, kind) do
    prefix = if delta >= 0, do: "+", else: ""
    "#{prefix}#{fmt_metric(delta, kind)}"
  end

  defp delta_class(delta) when delta > 0, do: "text-warning"
  defp delta_class(_), do: nil

  defp fmt_time(%NaiveDateTime{} = ndt), do: Calendar.strftime(ndt, "%m-%d %H:%M")

  defp uptime(%DateTime{} = started_at), do: uptime(started_at, NaiveDateTime.utc_now())

  # uptime as of a specific sample — a stale pod's uptime must not keep
  # growing after the pod died
  defp uptime(%DateTime{} = started_at, %NaiveDateTime{} = as_of) do
    as_of = DateTime.from_naive!(as_of, "Etc/UTC")
    format_duration(DateTime.diff(as_of, started_at))
  end

  defp format_duration(seconds) do
    days = div(seconds, 86_400)
    hours = div(rem(seconds, 86_400), 3600)
    minutes = div(rem(seconds, 3600), 60)

    cond do
      days > 0 -> "#{days}d #{hours}h"
      hours > 0 -> "#{hours}h #{minutes}m"
      true -> "#{minutes}m"
    end
  end

  defp age(%NaiveDateTime{} = inserted_at) do
    seconds = NaiveDateTime.diff(NaiveDateTime.utc_now(), inserted_at)

    if seconds < 60, do: "#{seconds}s", else: "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
  end
end
