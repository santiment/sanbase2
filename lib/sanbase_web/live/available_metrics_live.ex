defmodule SanbaseWeb.AvailableMetricsLive do
  use SanbaseWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    metrics_map = get_metrics() |> Map.new(fn m -> {m.api_name, m} end)
    visible_metrics = metrics_map |> Map.keys() |> Enum.sort(:asc)

    {:ok,
     socket
     |> assign(
       visible_metrics: visible_metrics,
       metrics_map: metrics_map
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex justify-center">
      <div class="grid">
        <.controls />
        <.table id="available_metrics" rows={Map.take(@metrics_map, @visible_metrics) |> Map.values()}>
          <:col :let={row} label="API Name"><%= row.api_name %></:col>
          <:col :let={row} label="Internal Name"><%= row.internal_name %></:col>
          <:col :let={row} label="Docs">
            <.docs_links docs={row.docs} />
          </:col>
          <:col :let={row} label="Sanbase Access"><%= row.sanbase_access %></:col>
          <:col :let={row} label="SanAPI Access"><%= row.sanapi_access %></:col>
          <:col :let={row} label="Frequency"><%= row.frequency %></:col>
          <:col :let={row} label="Available Assets">
            <.available_assets assets={row.available_assets} />
          </:col>
        </.table>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("apply_controls", params, socket) do
    visible_metrics =
      socket.assigns.metrics_map
      |> Map.values()
      |> maybe_apply_filter(:only_with_docs, params)
      |> maybe_apply_filter(:only_intraday_metrics, params)
      |> maybe_apply_filter(:match_metric_name, params)
      |> Enum.map(& &1.api_name)

    {:noreply,
     socket
     |> assign(:visible_metrics, visible_metrics)}
  end

  defp maybe_apply_filter(metrics, :only_with_docs, %{"only_with_docs" => "on"}) do
    metrics
    |> Enum.filter(&(&1.docs != []))
  end

  defp maybe_apply_filter(metrics, :only_intraday_metrics, %{"only_intraday_metrics" => "on"}) do
    metrics
    |> Enum.filter(&(&1.frequency_seconds < 86400))
  end

  defp maybe_apply_filter(metrics, :match_metric_name, %{"match_metric_name" => str}) do
    metrics
    |> Enum.filter(&String.contains?(&1.api_name, str))
  end

  defp maybe_apply_filter(metrics, _, _), do: metrics

  defp get_metrics() do
    metrics = Sanbase.Metric.available_metrics()

    metrics
    |> Enum.map(fn metric ->
      {:ok, m} = Sanbase.Metric.metadata(metric)

      %{
        api_name: m.metric,
        internal_name: m.metric,
        docs: Map.get(m, :docs) || [],
        available_assets: [],
        frequency: m.min_interval,
        frequency_seconds: Sanbase.DateTimeUtils.str_to_sec(m.min_interval),
        sanbase_access: "free",
        sanapi_access: "free"
      }
    end)
    |> Enum.sort_by(& &1.api_name, :asc)
  end

  defp controls(assigns) do
    ~H"""
    <div>
      <form phx-change="apply_controls" class="flex space-x-8">
        <div>
          <input type="checkbox" name="only_with_docs" />
          <label>Only metrics with docs</label>
        </div>

        <div>
          <input type="checkbox" name="only_intraday_metrics" />
          <label>Only intraday metrics</label>
        </div>

        <div>
          <input
            type="text"
            name="match_metric_name"
            phx-debounce="200"
            placeholder="Filter by metric name"
          />
        </div>
      </form>
    </div>
    """
  end

  defp available_assets(assigns) do
    ~H"""
    <span>
      bitcoin, ethereum, xrp, ...
    </span>
    """
  end

  defp docs_links(assigns) do
    ~H"""
    <div class="flex flex-row">
      <a :for={doc <- assigns.docs} href={doc.link} target="_blank">
        Open Docs
      </a>
    </div>
    """
  end
end
