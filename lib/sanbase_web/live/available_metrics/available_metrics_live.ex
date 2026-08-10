defmodule SanbaseWeb.AvailableMetricsLive do
  use SanbaseWeb, :live_view

  import SanbaseWeb.AvailableMetricsDescription
  alias SanbaseWeb.AvailableMetricsComponents
  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.Category.MetricGroup

  @impl true
  def mount(_params, _session, socket) do
    metrics_map = Sanbase.AvailableMetrics.get_metrics_map()
    categories = MetricCategory.list_ordered()
    groups_by_category = groups_by_category_id()

    default_filter = %{"only_asset_metrics" => "on", "only_with_docs" => "on"}

    visible_metrics =
      metrics_map
      |> Sanbase.AvailableMetrics.apply_filters(default_filter)
      |> Enum.map(& &1.metric)

    {:ok,
     socket
     |> assign(
       page_title: "Santiment | Available Metrics",
       visible_metrics: visible_metrics,
       metrics_map: metrics_map,
       filter: default_filter,
       categories: categories,
       groups_by_category: groups_by_category,
       groups_for_selected_category: []
     )}
  end

  @impl true
  def render(assigns) do
    ordered_visible_metrics =
      Map.take(assigns.metrics_map, assigns.visible_metrics)
      |> Map.values()
      |> Enum.sort_by(& &1.metric, :asc)

    total_assets_with_metrics =
      Enum.reduce(
        ordered_visible_metrics,
        MapSet.new(),
        &MapSet.union(MapSet.new(&1.available_assets), &2)
      )
      |> MapSet.size()

    assigns =
      assigns
      |> assign(
        ordered_visible_metrics: ordered_visible_metrics,
        assets_count: total_assets_with_metrics
      )

    ~H"""
    <div class="flex flex-col items-start justify-evenly">
      <.filters
        filter={@filter}
        categories={@categories}
        groups_for_selected_category={@groups_for_selected_category}
      />
      <div class="text-base-content/50 text-sm py-2">
        <div>
          Showing {length(@visible_metrics)} metrics
        </div>
        <div>
          In total {to_string(@assets_count)} assets are supported by at least one of the visible filtered metrics
        </div>
      </div>
      <AvailableMetricsComponents.table_with_popover_th
        id="available_metrics"
        rows={@ordered_visible_metrics}
      >
        <:col
          :let={row}
          label="Name"
          popover_target="popover-name"
          popover_target_text={get_popover_text(%{key: "Name"})}
          col_class="min-w-[18rem] whitespace-nowrap"
        >
          {row.metric}
        </:col>
        <:col
          :let={row}
          label="Category"
          popover_target="popover-category"
          popover_target_text={get_popover_text(%{key: "Category"})}
          col_class="min-w-[10rem] whitespace-nowrap"
        >
          <.categorization_names names={category_names(row.categories)} />
        </:col>
        <:col
          :let={row}
          label="Group"
          popover_target="popover-group"
          popover_target_text={get_popover_text(%{key: "Group"})}
          col_class="min-w-[10rem] whitespace-nowrap"
        >
          <.categorization_names names={group_names(row.categories)} />
        </:col>
        <:col
          :let={row}
          label="Frequency"
          popover_target="popover-frequency"
          popover_target_text={get_popover_text(%{key: "Frequency"})}
          col_class="whitespace-nowrap"
        >
          {row.frequency}
        </:col>

        <:col
          :let={row}
          label="Stabilization Period"
          popover_target="popover-stabilization-period"
          popover_target_text={get_popover_text(%{key: "Stabilization Period"})}
          col_class="whitespace-nowrap"
        >
          {row.stabilization_period}
        </:col>

        <:col
          :let={row}
          label="Can Mutate"
          popover_target="popover-can-mutate"
          popover_target_text={get_popover_text(%{key: "Can Mutate"})}
          col_class="whitespace-nowrap"
        >
          {row.can_mutate}
        </:col>
        <:col
          :let={row}
          label="Selectors"
          popover_target="popover-selectors"
          popover_target_text={get_popover_text(%{key: "Available Selectors"})}
          col_class="min-w-[8rem] whitespace-nowrap"
        >
          <.available_selectors selectors={row.available_selectors} />
        </:col>
        <:col
          :let={row}
          label="Default Aggregation"
          popover_target="popover-default-aggregation"
          popover_target_text={get_popover_text(%{key: "Default Aggregation"})}
          col_class="whitespace-nowrap"
        >
          {row.default_aggregation |> to_string() |> String.upcase()}
        </:col>
        <:col
          :let={row}
          label="Access"
          popover_target="popover-access"
          popover_target_text={get_popover_text(%{key: "Access"})}
          col_class="whitespace-nowrap"
        >
          <.metric_access access={row.access} />
        </:col>
        <:col
          :let={row}
          label="Available Assets"
          col_class="min-w-[14rem] whitespace-nowrap"
          popover_target="popover-available-assets"
          popover_target_text={get_popover_text(%{key: "Available Assets"})}
        >
          <.available_assets assets={row.available_assets} />
        </:col>
        <:col
          :let={row}
          label="Docs"
          popover_target="popover-docs"
          popover_target_text={get_popover_text(%{key: "Docs"})}
          col_class="whitespace-nowrap"
        >
          <.docs_links docs={row.docs} />
        </:col>
        <:col
          :let={row}
          label="Metric Details"
          popover_target="popover-metric-details"
          popover_target_text={get_popover_text(%{key: "Metric Details"})}
          col_class="whitespace-nowrap"
        >
          <.metric_details_button metric={row.metric} />
        </:col>
      </AvailableMetricsComponents.table_with_popover_th>
    </div>
    """
  end

  @impl true
  def handle_event("apply_filters", params, socket) do
    params = maybe_reset_group_for_category(params, socket.assigns.groups_by_category)

    visible_metrics =
      socket.assigns.metrics_map
      |> Sanbase.AvailableMetrics.apply_filters(params)
      |> Enum.map(& &1.metric)

    {:noreply,
     socket
     |> assign(
       visible_metrics: visible_metrics,
       filter: params,
       groups_for_selected_category:
         groups_for_category(params, socket.assigns.groups_by_category)
     )}
  end

  @doc ~s"""
  Checkbox that display description on hover.
  """
  attr :popover_text, :string, required: true
  attr :popover_target, :string, required: true
  attr :input_id, :string, required: true
  attr :input_name, :string, required: true
  attr :input_checked, :boolean, required: true
  attr :input_label, :string, required: true

  def checkbox_with_popover(assigns) do
    ~H"""
    <div class="flex items-center">
      <input
        id={@input_id}
        type="checkbox"
        name={@input_name}
        checked={@input_checked}
        class="checkbox checkbox-sm hover:cursor-pointer"
      />
      <%!-- The popover wraps only the label. Wrapping the checkbox in a daisyUI
      dropdown trigger breaks it: daisyUI sets `pointer-events: none` on the
      `[tabindex]` trigger while the dropdown has focus within it, so the click
      that focuses the checkbox also kills the click that would toggle it. --%>
      <div class="dropdown dropdown-hover dropdown-bottom">
        <label
          for={@input_id}
          class="ms-2 text-sm font-medium border-b border-dotted hover:cursor-pointer"
        >
          {@input_label}
        </label>
        <div
          id={@popover_target}
          class="dropdown-content card card-compact bg-base-100 border border-base-300 shadow-2xl z-10 w-80 text-justify px-8 py-6 text-sm font-medium text-base-content/70"
        >
          <span>{@popover_text}</span>
        </div>
      </div>
    </div>
    """
  end

  defp filters(assigns) do
    ~H"""
    <div>
      <form
        phx-change="apply_filters"
        class="flex flex-col flex-wrap space-y-2 items-start md:flex-row md:items-center md:gap-x-8"
      >
        <.checkbox_with_popover
          popover_text="Show the metrics that are available for assets. Exlude metrics that are computed only for other selectors like ecosystem, contracts, etc."
          popover_target="popover-with-assets"
          input_id="with-assets-checkbox"
          input_name="only_asset_metrics"
          input_checked={@filter["only_asset_metrics"] == "on"}
          input_label="Filter asset metrics"
        />

        <.checkbox_with_popover
          popover_text="Show only the metrics that have documentation"
          popover_target="popover-with-docs"
          input_id="with-docs-checkbox"
          input_name="only_with_docs"
          input_checked={@filter["only_with_docs"] == "on"}
          input_label="Only with docs"
        />

        <div>
          <select
            id="category-filter"
            name="category_id"
            class="select select-bordered select-sm w-56"
          >
            <option value="all" selected={category_selected?(@filter["category_id"], "all")}>
              All categories
            </option>
            <option value="none" selected={@filter["category_id"] == "none"}>
              Uncategorized
            </option>
            <option
              :for={category <- @categories}
              value={category.id}
              selected={to_string(@filter["category_id"]) == to_string(category.id)}
            >
              {category.name}
            </option>
          </select>
        </div>

        <div>
          <select id="group-filter" name="group_id" class="select select-bordered select-sm w-56">
            <option value="all" selected={group_selected?(@filter["group_id"], "all")}>
              All groups
            </option>
            <option value="none" selected={@filter["group_id"] == "none"}>
              Ungrouped
            </option>
            <option
              :for={group <- @groups_for_selected_category}
              value={group.id}
              selected={to_string(@filter["group_id"]) == to_string(group.id)}
            >
              {group.name}
            </option>
          </select>
        </div>

        <div>
          <input
            type="search"
            id="metric-name-search"
            value={@filter["match_metric_name"] || ""}
            name="match_metric_name"
            class="input input-sm w-64"
            placeholder="Filter by metric"
            phx-debounce="200"
          />
        </div>

        <div>
          <input
            type="search"
            id="metric-supports_asset"
            value={@filter["metric_supports_asset"] || ""}
            name="metric_supports_asset"
            class="input input-sm w-64"
            placeholder="Filter by supported asset"
            phx-debounce="200"
          />
        </div>
        <AvailableMetricsComponents.available_metrics_button
          text="Download as CSV"
          icon="hero-arrow-down-tray"
          href={~p"/export_available_metrics?#{%{filter: Jason.encode!(@filter)}}"}
        />
      </form>
    </div>
    """
  end

  defp available_assets(assigns) do
    {first_2, rest} = Enum.split(assigns.assets, 2)
    first_2_str = Enum.join(first_2, ", ")

    rest_str = if rest != [], do: " and #{length(rest)} more", else: ""

    assigns =
      assigns
      |> assign(first_2_str: first_2_str, rest_str: rest_str)

    ~H"""
    <span>
      {@first_2_str}
      <span class="text-base-content/50">{@rest_str}</span>
    </span>
    """
  end

  defp docs_links(assigns) do
    ~H"""
    <div class="flex flex-row">
      <AvailableMetricsComponents.available_metrics_button
        :for={doc <- assigns.docs}
        href={doc.link}
        text="Docs"
        icon="hero-clipboard-document-list"
      />
    </div>
    """
  end

  defp metric_details_button(assigns) do
    ~H"""
    <AvailableMetricsComponents.available_metrics_button
      text="Details"
      href={~p"/available_metrics/#{@metric}"}
      icon="hero-arrow-top-right-on-square"
    />
    """
  end

  defp available_selectors(assigns) do
    assigns =
      assign(assigns,
        selectors_str:
          assigns.selectors
          |> List.wrap()
          |> Enum.map(&(&1 |> to_string() |> String.upcase()))
          |> Enum.join(", ")
      )

    ~H"""
    <span>{@selectors_str}</span>
    """
  end

  defp metric_access(assigns) do
    access_string =
      case assigns.access do
        %{"historical" => :free, "realtime" => :free} -> "FREE"
        _ -> "RESTRICTED"
      end

    assigns =
      assigns |> assign(:access_string, access_string)

    ~H"""
    <span>{@access_string}</span>
    """
  end

  defp categorization_names(assigns) do
    ~H"""
    <span :if={@names == []} class="text-base-content/40">—</span>
    <span :if={@names != []}>{Enum.join(@names, ", ")}</span>
    """
  end

  defp category_names(categories) do
    categories
    |> Enum.map(& &1.category_name)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp group_names(categories) do
    hidden = Sanbase.AvailableMetrics.hidden_group_names()

    categories
    |> Enum.map(& &1.group_name)
    |> Enum.reject(&(is_nil(&1) or &1 in hidden))
    |> Enum.uniq()
  end

  defp category_selected?(nil, "all"), do: true
  defp category_selected?("", "all"), do: true
  defp category_selected?("all", "all"), do: true
  defp category_selected?(value, expected), do: value == expected

  defp group_selected?(nil, "all"), do: true
  defp group_selected?("", "all"), do: true
  defp group_selected?("all", "all"), do: true
  defp group_selected?(value, expected), do: value == expected

  defp groups_by_category_id do
    hidden = Sanbase.AvailableMetrics.hidden_group_names()

    MetricGroup.list_with_category()
    |> Enum.reject(&(&1.name in hidden))
    |> Enum.group_by(& &1.category_id)
  end

  defp groups_for_category(filter, groups_by_category) do
    case Map.get(filter, "category_id") do
      category_id when category_id in [nil, "", "all", "none"] ->
        []

      category_id when is_binary(category_id) ->
        case Integer.parse(category_id) do
          {id, ""} -> Map.get(groups_by_category, id, [])
          _ -> []
        end

      category_id when is_integer(category_id) ->
        Map.get(groups_by_category, category_id, [])

      _ ->
        []
    end
  end

  defp maybe_reset_group_for_category(params, groups_by_category) do
    group_id = Map.get(params, "group_id")
    groups = groups_for_category(params, groups_by_category)
    valid_group_ids = MapSet.new(groups, &to_string(&1.id))

    cond do
      group_id in [nil, "", "all", "none"] ->
        params

      MapSet.member?(valid_group_ids, to_string(group_id)) ->
        params

      true ->
        Map.put(params, "group_id", "all")
    end
  end
end
