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

  alias Sanbase.Monitoring.MemoryStat

  @live_window_minutes 5
  @series_hours 24
  @samples_shown 120
  @refresh_interval 60_000

  @diff_metrics [
    {:rss_bytes, "OS RSS", :bytes},
    {:vm_total_bytes, "VM total", :bytes},
    {:vm_processes_bytes, "VM processes", :bytes},
    {:vm_binary_bytes, "VM binary", :bytes},
    {:vm_ets_bytes, "VM ETS", :bytes},
    {:vm_code_bytes, "VM code", :bytes},
    {:alloc_used_bytes, "Alloc used (blocks)", :bytes},
    {:alloc_allocated_bytes, "Alloc allocated (carriers)", :bytes},
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
       samples_shown: @samples_shown
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

  defp load_data(socket) do
    pods = MemoryStat.latest_per_pod(@live_window_minutes)
    selected_pod = socket.assigns.selected_pod

    socket = assign(socket, :pods, pods)

    case Enum.find(pods, &(&1.pod_name == selected_pod)) do
      nil ->
        assign(socket, selected: nil, series: [], diff_rows: nil, details_stat: nil)

      latest ->
        series = MemoryStat.pod_series(selected_pod, @series_hours)

        assign(socket,
          selected: latest,
          series: series,
          diff_rows: incarnation_diff(series, latest),
          details_stat: MemoryStat.latest_details(selected_pod)
        )
    end
  end

  # Diff oldest-vs-newest sample of the CURRENT BEAM incarnation only —
  # stitching across a restart would show a bogus huge drop.
  defp incarnation_diff(series, latest) do
    case Enum.filter(series, &(&1.beam_started_at == latest.beam_started_at)) do
      [first | _] = same when length(same) > 1 ->
        last = List.last(same)

        %{
          from: first.inserted_at,
          to: last.inserted_at,
          rows:
            for {key, label, kind} <- @diff_metrics,
                first_value = Map.get(first, key),
                last_value = Map.get(last, key),
                is_integer(first_value) and is_integer(last_value) do
              %{
                label: label,
                kind: kind,
                first: first_value,
                last: last_value,
                delta: last_value - first_value
              }
            end
        }

      _ ->
        nil
    end
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

      <section>
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
              <tr :if={@pods == []}>
                <td colspan="12" class="text-center text-base-content/50">
                  No pods reported recently. Is Sanbase.Monitoring.MemoryCollector enabled?
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <div :if={@selected_pod && is_nil(@selected)} class="alert alert-warning">
        Pod {@selected_pod} has not reported in the last {@live_window_minutes} minutes.
        It may have been replaced by a newer deployment.
      </div>

      <%= if @selected do %>
        <section>
          <.section_heading>{@selected.pod_name} · latest sample</.section_heading>
          <div class="grid gap-2 grid-cols-2 sm:grid-cols-4 lg:grid-cols-8">
            <.stat_card label="OS RSS" value={fmt_bytes(@selected.rss_bytes)} />
            <.stat_card label="VM total" value={fmt_bytes(@selected.vm_total_bytes)} />
            <.stat_card label="Processes mem" value={fmt_bytes(@selected.vm_processes_bytes)} />
            <.stat_card label="Binary" value={fmt_bytes(@selected.vm_binary_bytes)} />
            <.stat_card label="ETS" value={fmt_bytes(@selected.vm_ets_bytes)} />
            <.stat_card label="Process count" value={@selected.process_count} />
            <.stat_card label="Atoms" value={@selected.atom_count} />
            <.stat_card label="Uptime" value={uptime(@selected.beam_started_at)} />
          </div>
        </section>

        <section :if={@diff_rows}>
          <.section_heading>
            Change over current incarnation
            ({fmt_time(@diff_rows.from)} → {fmt_time(@diff_rows.to)} UTC)
          </.section_heading>
          <div class="overflow-x-auto bg-base-100 border border-base-300 rounded">
            <table class="table table-sm">
              <thead>
                <tr class="text-base-content/60">
                  <th>Metric</th>
                  <th class="text-right">Start</th>
                  <th class="text-right">Now</th>
                  <th class="text-right">Change</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @diff_rows.rows} class="hover:bg-base-200">
                  <td class="font-medium">{row.label}</td>
                  <td class="text-right tabular-nums">{fmt_metric(row.first, row.kind)}</td>
                  <td class="text-right tabular-nums">{fmt_metric(row.last, row.kind)}</td>
                  <td class={["text-right tabular-nums", delta_class(row.delta)]}>
                    {fmt_delta(row.delta, row.kind)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <div :if={details(@details_stat) != %{}} class="grid grid-cols-1 lg:grid-cols-2 gap-3">
          <section :if={details(@details_stat)["top_ets"]}>
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

          <section :if={details(@details_stat)["process_groups"]}>
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

        <section>
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
      <% end %>
    </div>
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

  defp alloc_unused(%{alloc_used_bytes: used, alloc_allocated_bytes: allocated})
       when is_integer(used) and is_integer(allocated),
       do: allocated - used

  defp alloc_unused(_), do: nil

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

  defp uptime(%DateTime{} = started_at) do
    seconds = DateTime.diff(DateTime.utc_now(), started_at)
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

    if seconds < 60 do
      "#{seconds}s"
    else
      "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
    end
  end
end
