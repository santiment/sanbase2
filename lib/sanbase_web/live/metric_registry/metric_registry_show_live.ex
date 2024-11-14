defmodule SanbaseWeb.MetricRegistryShowLive do
  use SanbaseWeb, :live_view

  import SanbaseWeb.CoreComponents
  import SanbaseWeb.AvailableMetricsDescription

  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok, metric_registry} = Sanbase.Metric.Registry.by_id(id)
    rows = get_rows(metric_registry)

    {:ok,
     socket
     |> assign(
       metric_registry: metric_registry,
       rows: rows
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-7/8">
      <h1 class="text-gray-800 text-2xl">
        Showing details for <span class="text-blue-700"><%= @metric_registry.metric %></span>
      </h1>
      <div class="my-4">
        <AvailableMetricsComponents.available_metrics_button
          text="Back to Metric Registry"
          href={~p"/admin2/metric_registry"}
          icon="hero-arrow-uturn-left"
        />

        <AvailableMetricsComponents.available_metrics_button
          text="Edit Metric"
          href={~p"/admin2/metric_registry/edit/#{@metric_registry}"}
          icon="hero-pencil-square"
        />
      </div>
      <.table id="metric_registry" rows={@rows}>
        <:col :let={row} col_class="w-40">
          <AvailableMetricsComponents.popover
            display_text={row.key}
            popover_target={Map.get(row, :popover_target)}
            popover_target_text={Map.get(row, :popover_target_text)}
          />
        </:col>

        <:col :let={row}>
          <.formatted_value key={row.key} value={row.value} />
        </:col>
      </.table>
    </div>
    """
  end

  defp formatted_value(assigns) do
    value =
      assigns.value
      |> List.wrap()
      |> Enum.join(", ")

    assigns = assign(assigns, :value, value)

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

  defp get_rows(metric_registry) do
    [
      %{
        key: "Metric",
        value: metric_registry.metric,
        popover_target: "popover-name",
        popover_target_text: get_popover_text(%{key: "Name"})
      },
      %{
        key: "Internal Metric",
        value: metric_registry.internal_metric,
        popover_target: "popover-internal-name",
        popover_target_text: get_popover_text(%{key: "Internal Name"})
      },
      %{
        key: "Aliases",
        value: metric_registry.aliases |> Enum.map(& &1.name) |> Enum.join(", "),
        popover_target: "popover-aliases",
        popover_target_text: get_popover_text(%{key: "Alias"})
      },
      %{
        key: "Table",
        value: metric_registry.tables |> Enum.map(& &1.name) |> Enum.join(", "),
        popover_target: "popover-clickhouse-table",
        popover_target_text: get_popover_text(%{key: "Clickhouse Table"})
      },
      %{
        key: "Min Interval",
        value: metric_registry.min_interval,
        popover_target: "popover-frequency",
        popover_target_text: get_popover_text(%{key: "Frequency"})
      },
      %{
        key: "SANBASE Min Plan",
        value: metric_registry.sanbase_min_plan,
        popover_target: "popover-sanbase-min-plan",
        popover_target_text: get_popover_text(%{key: "Min Plan"})
      },
      %{
        key: "SANAPI Min Plan",
        value: metric_registry.sanapi_min_plan,
        popover_target: "popover-sanapi-min-plan",
        popover_target_text: get_popover_text(%{key: "Min Plan"})
      },
      %{
        key: "Docs",
        value: metric_registry.docs |> Enum.map(& &1.link) |> Enum.join(", "),
        popover_target: "popover-docs",
        popover_target_text: get_popover_text(%{key: "Docs"})
      },
      %{
        key: "Has Incomplete Data",
        value: metric_registry.has_incomplete_data,
        popover_target: "popover-incomplete-data",
        popover_target_text: get_popover_text(%{key: "Has Incomplete Data"})
      },
      %{
        key: "Default Aggregation",
        value: stringify(metric_registry.default_aggregation),
        popover_target: "popover-default-aggregation",
        popover_target_text: get_popover_text(%{key: "Default Aggregation"})
      },
      %{
        key: "Access",
        value: metric_registry.access,
        popover_target: "popover-access",
        popover_target_text: get_popover_text(%{key: "Access"})
      },
      %{
        key: "Is Timebound",
        value: metric_registry.is_timebound,
        popover_target: "popover-timebound",
        popover_target_text: get_popover_text(%{key: "Is Timebound"})
      },
      %{
        key: "Is Template Metric",
        value: metric_registry.is_template,
        popover_target: "popover-template-metric",
        popover_target_text: get_popover_text(%{key: "Is Template Metric"})
      },
      %{
        key: "Parameters",
        value: Jason.encode!(metric_registry.parameters),
        popover_target: "popover-parameters",
        popover_target_text: get_popover_text(%{key: "Parameters"})
      },
      %{
        key: "Fixed Parameters",
        value: Jason.encode!(metric_registry.fixed_parameters),
        popover_target: "popover-parameters",
        popover_target_text: get_popover_text(%{key: "Fixed Parameters"})
      },
      %{
        key: "Aggregations",
        value: Jason.encode!(Sanbase.Metric.Registry.aggregations()),
        popover_target: "popover-aggregations",
        popover_target_text: get_popover_text(%{key: "Available Aggregations"})
      },
      %{
        key: "Selectors",
        value:
          metric_registry.selectors
          |> Enum.map(&Map.delete(Map.from_struct(&1), :id))
          |> Jason.encode!(),
        popover_target: "popover-selectors",
        popover_target_text: get_popover_text(%{key: "Available Selectors"})
      },
      %{
        key: "Required Selectors",
        value:
          metric_registry.required_selectors
          |> Enum.map(&Map.delete(Map.from_struct(&1), :id))
          |> Jason.encode!(),
        popover_target: "popover-required-selectors",
        popover_target_text: get_popover_text(%{key: "Required Selectors"})
      },
      %{
        key: "Data Type",
        value: metric_registry.data_type,
        popover_target: "popover-data-type",
        popover_target_text: get_popover_text(%{key: "Data Type"})
      },
      %{
        key: "Is Deprecated",
        value: metric_registry.is_deprecated,
        popover_target: "popover-is-deprecated",
        popover_target_text: get_popover_text(%{key: "Is Deprecated"})
      },
      %{
        key: "Hard Deprecate After",
        value: metric_registry.hard_deprecate_after,
        popover_target: "popover-hard-deprecate-after",
        popover_target_text: get_popover_text(%{key: "Hard Deprecate After"})
      },
      %{
        key: "Deprecation Note",
        value: metric_registry.deprecation_note,
        popover_target: "popover-deprecation-note",
        popover_target_text: get_popover_text(%{key: "Deprecation Note"})
      }
    ]
  end
end
