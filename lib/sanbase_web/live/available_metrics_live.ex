defmodule SanbaseWeb.AvailableMetricsLive do
  use SanbaseWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:rows, get_metrics())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex justify-evenly">
        <.table id="available_metrics" rows={@rows}>
          <:col :let={row} label="API Name"><%= row.api_name %></:col>
          <:col :let={row} label="Internal Name"><%= row.internal_name %></:col>
          <:col :let={row} label="Docs">
            <.docs_links links={row.docs} />
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

  defp available_assets(assigns) do
    ~H"""
    <span>
      bitcoin, ethereum, xrp, ...
    </span>
    """
  end

  defp get_metrics() do
    metrics = Sanbase.Metric.available_metrics()

    metrics
    |> Enum.map(fn metric ->
      {:ok, m} = Sanbase.Metric.metadata(metric)

      %{
        api_name: m.metric,
        internal_name: m.metric,
        docs: Map.get(m, :docs, []),
        available_assets: [],
        frequency: m.min_interval,
        sanbase_access: "free",
        sanapi_access: "free"
      }
    end)
  end

  defp docs_links(assigns) do
    ~H"""
    <div class="flex flex-row">
      <.link href="https://academy.santiment.net/metrics/mvrv">
        Open Docs
      </.link>
    </div>
    """
  end
end
