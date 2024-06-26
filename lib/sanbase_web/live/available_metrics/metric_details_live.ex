defmodule SanbaseWeb.MetricDetailsLive do
  use SanbaseWeb, :live_view

  import SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(%{"metric" => metric}, _session, socket) do
    rows = get_rows(metric)

    {:ok,
     socket
     |> assign(
       metric: metric,
       rows: rows
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-7/8">
      <h1 class="text-gray-800 text-2xl">
        Showing details for <span class="text-blue-700"><%= @metric %></span>
      </h1>
      <div class="my-4">
        <.available_metrics_button
          text="Back to Available Metrics"
          href={~p"/available_metrics"}
          icon="hero-arrow-uturn-left"
        />
      </div>
      <.table id="available_metrics" rows={@rows}>
        <:col :let={row} col_class="w-40">
          <div class="relative">
            <div
              data-popover-target={Map.get(row, :popover_target)}
              data-popover-style="light"
              data-popover-placement="right"
            >
              <span class="border-b border-dotted border-gray-500 hover:cursor-pointer">
                <%= row.key %>
              </span>
            </div>

            <div
              id={Map.get(row, :popover_target)}
              role="tooltip"
              class="absolute max-h-[580px] min-w-[860px] overflow-y-auto z-10 invisible inline-block px-8 py-6 text-sm font-medium text-gray-600 bg-white border border-gray-200 rounded-lg shadow-2xl sans"
            >
              <span class="[&>pre]:font-sans"><%= Map.get(row, :popover_target_text) %></span>
            </div>
          </div>
        </:col>

        <:col :let={row}>
          <.formatted_value key={row.key} value={row.value} />
        </:col>
      </.table>
    </div>
    """
  end

  @impl true
  def handle_event("apply_filters", params, socket) do
    visible_metrics =
      socket.assigns.metrics_map
      |> Sanbase.AvailableMetrics.apply_filters(params)
      |> Enum.map(& &1.metric)

    {:noreply,
     socket
     |> assign(
       visible_metrics: visible_metrics,
       filter: params
     )}
  end

  defp formatted_value(%{key: "Available Assets"} = assigns) do
    last_asset = Enum.at(assigns.value, -1)
    assigns = assign(assigns, :last_asset, last_asset)

    ~H"""
    <div class="w-3/4">
      <a :for={asset <- @value} href={SanbaseWeb.Endpoint.project_url(asset)}>
        <!-- Keep the template and span glued, otherwise there will be a white space -->
        <%= asset %><span :if={asset != @last_asset}>,</span>
      </a>
    </div>
    """
  end

  defp formatted_value(%{key: "Docs"} = assigns) do
    ~H"""
    <div class="flex flex-row">
      <.available_metrics_button
        :for={doc <- assigns.value}
        href={doc.link}
        text="Docs"
        icon="hero-clipboard-document-list"
      />
    </div>
    """
  end

  defp formatted_value(assigns) do
    ~H"""
    <div>
      <%= to_string(@value) %>
    </div>
    """
  end

  defp stringify(ll) do
    ll
    |> List.wrap()
    |> Enum.map(fn x -> x |> to_string() |> String.upcase() end)
    |> Enum.join(", ")
  end

  defp stringify_required_selectors(l) when is_list(l) do
    Enum.map(l, fn
      ll when is_list(ll) ->
        str = Enum.map(ll, fn x -> x |> to_string() |> String.upcase() end) |> Enum.join(" or ")
        if length(ll) > 1, do: "(#{str})", else: str

      x ->
        x |> to_string() |> String.upcase()
    end)
    |> Enum.join(" and ")
  end

  defp get_rows(metric) do
    {:ok, metadata} = Sanbase.Metric.metadata(metric)
    {:ok, assets} = Sanbase.AvailableMetrics.get_metric_available_slugs(metric)

    rows = [
      %{
        key: "Name",
        value: metric,
        popover_target: "popover-name",
        popover_target_text: get_popover_text(%{key: "Name"})
      },
      %{
        key: "Internal Name",
        value: metadata.internal_metric,
        popover_target: "popover-internal-name",
        popover_target_text: get_popover_text(%{key: "Internal Name"})
      },
      %{
        key: "Frequency",
        value: metadata.min_interval,
        popover_target: "popover-frequency",
        popover_target_text: get_popover_text(%{key: "Frequency"})
      },
      %{
        key: "Docs",
        value: metadata.docs || [],
        popover_target: "popover-docs",
        popover_target_text: get_popover_text(%{key: "Docs"})
      },
      %{
        key: "Has Incomplete Data",
        value: metadata.has_incomplete_data,
        popover_target: "popover-incomplete-data",
        popover_target_text: get_popover_text(%{key: "Has Incomplete Data"})
      },
      %{
        key: "Default Aggregation",
        value: stringify(metadata.default_aggregation),
        popover_target: "popover-default-aggregation",
        popover_target_text: get_popover_text(%{key: "Default Aggregation"})
      },
      %{
        key: "Is Timebound",
        value: metadata.is_timebound,
        popover_target: "popover-timebound",
        popover_target_text: get_popover_text(%{key: "Is Timebound"})
      },
      %{
        key: "Available Aggregations",
        value: stringify(metadata.available_aggregations),
        popover_target: "popover-available-aggregations",
        popover_target_text: get_popover_text(%{key: "Available Aggregations"})
      },
      %{
        key: "Available Selectors",
        value: stringify(metadata.available_selectors),
        popover_target: "popover-available-selectors",
        popover_target_text: get_popover_text(%{key: "Available Selectors"})
      },
      %{
        key: "Required Selectors",
        value: stringify_required_selectors(metadata.required_selectors),
        popover_target: "popover-required-selectors",
        popover_target_text: get_popover_text(%{key: "Required Selectors"})
      },
      %{
        key: "Data Type",
        value: metadata.data_type,
        popover_target: "popover-data-type",
        popover_target_text: get_popover_text(%{key: "Data Type"})
      },
      %{
        key: "Available Assets",
        value: assets,
        popover_target: "popover-available-assets",
        popover_target_text: get_popover_text(%{key: "Available Assets"})
      }
    ]

    # If there are no required selectors, do not include this row
    rows =
      if metadata.required_selectors == [],
        do: Enum.reject(rows, &(&1.key == "Required Selectors")),
        else: rows

    rows
  end

  defp get_popover_text(%{key: "Name"} = assigns) do
    ~H"""
    <pre>
    The name of the metric that is used in the public API.
    For example, if the metric is `price_usd` it is provided as the `metric` argument.

    Example:

      {
        getMetric(<b>metric: "price_usd"</b>){
          timeseriesData(asset: "ethereum" from: "utc_now-90d" to: "utc_now" interval: "1d"){
            datetime
            value
          }
        }
      }
    </pre>
    """
  end

  defp get_popover_text(%{key: "Internal Name"} = assigns) do
    ~H"""
    <pre>
    The name of the metric that is used in the database tables.
    The database tables are accessed through Santiment Queries when the
    user interacts with the data via SQL.

    How to use Santiment Queries, check <.link href={"https://academy.santiment.net/santiment-queries"} class="underline text-blue-600">this link</.link>
    </pre>
    """
  end

  defp get_popover_text(%{key: "Frequency"} = assigns) do
    ~H"""
    <pre>
    The minimum interval at which the metric is updated.

    For more details check <.link href="https://academy.santiment.net/metrics/details/frequency" class="underline text-blue-600">this link</.link>
    </pre>
    """
  end

  defp get_popover_text(%{key: "Docs"} = assigns) do
    ~H"""
    <pre>
    The link to the documentation page for the metric.
    </pre>
    """
  end

  defp get_popover_text(%{key: "Has Incomplete Data"} = assigns) do
    ~H"""
    <pre>
    A boolean that indicates whether the metric has incomplete data.
    Only daily metrics (metrics with Frequency of 1d or bigger) can have incomplete data.

    In some cases, if the day is not yet complete, the current value can be misleading.
    For instance, fetching daily active addresses at 12pm UTC would
    include only half a day's data, potentially making the metric value for that day appear too low.

    By default the incomplete data is not returned by the API.
    To obtain this last incomplete data point, provide the `includeIncompleteData` flag
    Example:
      {
        getMetric(metric: "daily_active_addresses"){
          timeseriesData(
            slug: "bitcoin"
            from: "utc_now-3d"
            to: "utc_now"
            <b>includeIncompleteData: true</b>){
              datetime
              value
            }
        }
      }
    </pre>
    """
  end

  defp get_popover_text(%{key: "Is Timebound"} = assigns) do
    ~H"""
    <pre>
    A boolean that indicates whether the metric is timebound.
    </pre>
    """
  end

  defp get_popover_text(%{key: "Available Aggregations"} = assigns) do
    ~H"""
    <pre>
    The available aggregations for the metric.

    The aggregation controls how multiple data points are combined into one.

    For example, if the metric is `price_usd`, the aggregation is `LAST`, and the
    interval is `1d`, then each data point will be represented by the last price in the
    given day.


    All aggregations except `OHLC` are queried the same way:

    Example:
      {
        getMetric(metric: "price_usd"){
          timeseriesData(
          slug: "bitcoin"
          from: "utc_now-90d"
          to: "utc_now"
          <b>aggregation: MAX</b>){
            datetime
            value
          }
        }
      }

    When `OHLC` aggregation is used, the result is fetched in a different way -
    use `valueOhlc` instead of `value`:

    Example:
      {
        getMetric(metric: "price_usd"){
          timeseriesData(
          slug: "bitcoin"
          from: "utc_now-90d"
          to: "utc_now"
          <b>aggregation: OHLC</b>){
            datetime
            <b>valueOhlc {
              open high close low
            }</b>
          }
        }
      }
    </pre>
    """
  end

  defp get_popover_text(%{key: "Default Aggregation"} = assigns) do
    ~H"""
    <pre>
    The default aggregation for the metric.

    The default aggregation is hand picked so it makes most sense for the given metric.

    For example, the default aggregation for `price_usd` is `LAST`, as other aggregations like
    `SUM` do not make sense for that metric.

    To override the default aggregation, provide the `aggregation` parameter.

    Example:
      {
        getMetric(metric: "price_usd"){
          timeseriesData(
          slug: "bitcoin"
          from: "utc_now-90d"
          to: "utc_now"
          <b>aggregation: MAX</b>){
            datetime
            value
          }
        }
      }
    </pre>
    """
  end

  defp get_popover_text(%{key: "Available Selectors"} = assigns) do
    ~H"""
    <pre>
    The available selectors for the metric.

    The selectors control what entity the data is fetched for.
    For example, if the metric is `price_usd`, the selector is `asset`, and the
    value is `ethereum`, then the data will be fetched for.

    To provide any selector other than `slug`, use the `selector` input parameter.

    Example:
      {
        getMetric(metric: "active_withdrawals_per_exchange"){
          timeseriesData(
          <b>selector: { slug: "bitcoin" owner: "binance" }</b>
          from: "utc_now-90d"
          to: "utc_now"){
            datetime
            value
          }
        }
      }
    </pre>
    """
  end

  defp get_popover_text(%{key: "Required Selectors"} = assigns) do
    ~H"""
    <pre>
    The required selectors for the metric.

    This list includes the selectors that must be provided in order to get data.
    Not providing the required selectors will lead to an error and no data will be returned.

    Check the information for `Available Selectors` for an example.
    </pre>
    """
  end

  defp get_popover_text(%{key: "Data Type"} = assigns) do
    ~H"""
    <pre>
    The data type of the metric.
    The data type is used to determine how the data is stored and fetched.

    All metrics with `timeseries` data type are fetched in a generic way using `timeseriesData` field.

    Example:
      {
        getMetric(metric: "price_usd"){
          <b>timeseriesData</b>(
            slug: "bitcoin"
            from: "utc_now-90d"
            to: "utc_now"){
              datetime
              value
            }
        }
      }

    The metrics with `histogram` data type are fetched in different ways as their result format
    could differ. Check the documentation of each such metric to see an example.
    </pre>
    """
  end

  defp get_popover_text(%{key: "Available Assets"} = assigns) do
    ~H"""
    <pre>
    The assets for which the metric is available.
    The metric can be fetched for any of the listed assets.

    Each asset is uniquely identified by its `slug`:

    Example:
      {
        getMetric(metric: "daily_active_addresses"){
          timeseriesData(
            <b>slug: "bitcoin"</b>
            from: "utc_now-90d"
            to: "utc_now"){
              datetime
              value
            }
        }
      }
    </pre>
    """
  end
end
