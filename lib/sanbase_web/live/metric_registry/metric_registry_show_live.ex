defmodule SanbaseWeb.MetricRegistryShowLive do
  use SanbaseWeb, :live_view

  import SanbaseWeb.CoreComponents
  import SanbaseWeb.AvailableMetricsDescription

  alias Sanbase.Metric.Registry.Permissions
  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok, metric_registry} = Sanbase.Metric.Registry.by_id(id)
    rows = get_rows(metric_registry)

    # The URL is nil if no slug is supported
    # TODO: Extend the selector by using the required_selectors field
    metric_graphiql_url = metric_graphiql_url(metric_registry)

    {:ok,
     socket
     |> assign(
       page_title: "Metric Registry | Show #{metric_registry.metric}",
       metric_registry: metric_registry,
       metric_graphiql_url: metric_graphiql_url,
       rows: rows
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-7/8">
      <h1 class="text-blue-700 text-2xl mb-4">
        Metric Registry Details | {@metric_registry.metric}
      </h1>
      <SanbaseWeb.MetricRegistryComponents.user_details
        current_user={@current_user}
        current_user_role_names={@current_user_role_names}
      />
      <div class="my-4">
        <AvailableMetricsComponents.available_metrics_button
          text="Back to Metric Registry"
          href={~p"/admin/metric_registry"}
          icon="hero-arrow-uturn-left"
        />

        <AvailableMetricsComponents.available_metrics_button
          :if={Permissions.can?(:edit, roles: @current_user_role_names)}
          text="Edit Metric"
          href={~p"/admin/metric_registry/edit/#{@metric_registry}"}
          icon="hero-pencil-square"
        />

        <AvailableMetricsComponents.available_metrics_button
          :if={Permissions.can?(:see_history, roles: @current_user_role_names)}
          text="History"
          href={~p"/admin/metric_registry/history/#{@metric_registry}"}
          icon="hero-calendar-days"
        />

        <AvailableMetricsComponents.available_metrics_button
          :if={Permissions.can?(:see_history, roles: @current_user_role_names)}
          text="Diff Since Last Sync"
          href={~p"/admin/metric_registry/diff/#{@metric_registry}"}
          icon="hero-code-bracket-square"
        />

        <AvailableMetricsComponents.available_metrics_button
          :if={Permissions.can?(:edit, roles: @current_user_role_names)}
          text="Duplicate Metric"
          href={
            ~p"/admin/metric_registry/new?#{%{duplicate_metric_registry_id: @metric_registry.id}}"
          }
          icon="hero-document-duplicate"
        />

        <AvailableMetricsComponents.available_metrics_button
          text="Notifications"
          href={
            ~p"/admin/generic/search?resource=notifications&search[filters][0][field]=metric_registry_id&search[filters][0][value]=#{@metric_registry.id}"
          }
          icon="hero-envelope"
        />

        <AvailableMetricsComponents.available_metrics_button
          :if={Permissions.can?(:edit, roles: @current_user_role_names)}
          text="Test Metric"
          href={@metric_graphiql_url}
          icon="hero-rocket-launch"
          disabled={@metric_graphiql_url == nil}
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

  defp metric_graphiql_url(metric_registry) do
    result =
      case Sanbase.AvailableMetrics.get_metric_available_slugs(metric_registry.metric) do
        {:ok, slugs} ->
          # If we have precomputed the available slugs
          cond do
            # If ethereum/bitcoin are available, use them
            slugs == [] -> {:error, :no_slug_supported}
            "ethereum" in slugs -> {:ok, "ethereum"}
            "bitcoin" in slugs -> {:ok, "bitcoin"}
            true -> {:ok, Enum.random(slugs)}
          end

        {:error, _error} ->
          # Still generate the GraphiQL query, but populate it
          # with a placeholder slug. The function can return an error
          # if the available slugs list for a metric is still not
          # computed
          {:ok, "no_known_supported_slug_replace_me"}
      end

    case result do
      {:error, _} ->
        nil

      {:ok, slug} ->
        # Add aliases so the timeseries data is seen before the metadata
        # For many metrics the list of available assets has thousands of assets
        # and seeing the timeseries data will require a lot of scrolling
        query = """
        {
          getMetric(metric: "#{metric_registry.metric}"){
            R1_timeseries: timeseriesData(
              slug: "#{slug}"
              from: "utc_now-60d"
              to: "utc_now"
              interval: "7d"
            ){
              datetime
              value
             }

            R2_metadata: metadata {
              availableSlugs
            }
          }
        }
        """

        SanbaseWeb.Endpoint.backend_url() <> "/graphiql?query=#{URI.encode_www_form(query)}"
    end
  end

  defp formatted_value(assigns) do
    value =
      assigns.value
      |> List.wrap()
      |> Enum.join(", ")

    assigns = assign(assigns, :value, value)

    ~H"""
    <div>
      {to_string(@value)}
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
        key: "Human Readable Name",
        value: metric_registry.human_readable_name,
        popover_target: "popover-human-readable-name",
        popover_target_text: get_popover_text(%{key: "Human Readable Name"})
      },
      %{
        key: "Verified Status",
        value: to_verified_status(metric_registry.is_verified),
        popover_target: "popover-verified-status",
        popover_target_text: get_popover_text(%{key: "Verified Status"})
      },
      %{
        key: "Sync Status",
        value: String.upcase(metric_registry.sync_status) |> String.replace("_", " "),
        popover_target: "popover-sync-status",
        popover_target_text: get_popover_text(%{key: "Sync Status"})
      },
      %{
        key: "Last Sync Datetime",
        value: metric_registry.last_sync_datetime || "No Syncs",
        popover_target: "popover-last-sync-datetime",
        popover_target_text: get_popover_text(%{key: "Last Sync Datetime"})
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
        key: "Exposed Environments",
        value: metric_registry.exposed_environments,
        popover_target: "popover-exposed-environments",
        popover_target_text: get_popover_text(%{key: "Exposed Environments"})
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
      },
      %{
        key: "Status",
        value: metric_registry.status,
        popover_target: "popover-status",
        popover_target_text: get_popover_text(%{key: "Status"})
      }
    ]
  end

  defp to_verified_status(is_verified) do
    if is_verified, do: "VERIFIED", else: "UNVERIFIED"
  end
end
