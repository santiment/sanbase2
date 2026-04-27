defmodule SanbaseWeb.MetricDisplayOrderLive do
  use SanbaseWeb, :live_view

  import SanbaseWeb.AdminLiveHelpers, only: [parse_int: 2]

  alias Sanbase.Metric.UIMetadata.DisplayOrder
  alias SanbaseWeb.AdminSharedComponents

  @impl true
  def mount(_params, _session, socket) do
    ordered_data = DisplayOrder.get_ordered_metrics()
    metrics = ordered_data.metrics
    categories = ordered_data.categories

    first_category_name = if categories != [], do: List.first(categories).name, else: nil

    {:ok,
     socket
     |> assign(
       page_title: "Metric Display Order",
       metrics: metrics,
       categories: categories,
       selected_category: first_category_name,
       selected_group: nil,
       filtered_metrics: [],
       reordering: false,
       search_query: "",
       search_results: [],
       highlighted_metric_id: nil
     )
     |> filter_metrics()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    category = params["category"] || socket.assigns.selected_category
    group = params["group"]

    highlighted_metric_id =
      params["highlight_metric"] && parse_int(params["highlight_metric"], nil)

    {:noreply,
     socket
     |> assign(
       selected_category: category,
       selected_group: group,
       highlighted_metric_id: highlighted_metric_id
     )
     |> filter_metrics()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-full">
      <div class="text-2xl mb-4">
        Metric Display Order
      </div>

      <.navigation />

      <.search_box search_query={@search_query} />

      <.filters
        categories={@categories}
        selected_category={@selected_category}
        groups={@groups}
        selected_group={@selected_group}
        search_query={@search_query}
      />

      <.search_results :if={@search_results != []} search_results={@search_results} />

      <.metrics_table
        filtered_metrics={@filtered_metrics}
        highlighted_metric_id={@highlighted_metric_id}
      />

      <.modal :if={@reordering} id="reordering-modal" show>
        <.header>Reordering Metrics</.header>
        <div class="text-center py-4">
          <span class="loading loading-spinner loading-lg text-primary"></span>
          <p class="mt-4">Saving new order...</p>
        </div>
      </.modal>
    </div>
    """
  end

  def navigation(assigns) do
    ~H"""
    <div class="my-4 flex flex-row space-x-2">
      <AdminSharedComponents.nav_button
        text="Back to Metric Registry"
        href={~p"/admin/metric_registry"}
        icon="hero-home"
      />
      <AdminSharedComponents.nav_button
        text="Manage Categories"
        href={~p"/admin/metric_registry/categories"}
        icon="hero-rectangle-group"
      />
      <AdminSharedComponents.nav_button
        text="Manage Groups"
        href={~p"/admin/metric_registry/groups"}
        icon="hero-user-group"
      />
      <AdminSharedComponents.nav_button
        text="New Metric Display Order"
        href={~p"/admin/metric_registry/display_order/new"}
        icon="hero-plus"
      />
    </div>
    """
  end

  attr :categories, :list, required: true
  attr :selected_category, :string, required: true
  attr :groups, :list, required: true
  attr :selected_group, :any, required: true
  attr :search_query, :string, required: true

  def filters(assigns) do
    ~H"""
    <div class="flex flex-row space-x-4 mb-4">
      <div class="w-1/4">
        <.simple_form for={%{}} as={:filter} phx-change="filter">
          <.input
            type="select"
            name="category"
            value={@selected_category}
            label="Category"
            options={Enum.map(@categories, fn cat -> {cat.name, cat.name} end)}
          />
        </.simple_form>
      </div>

      <div :if={@groups && length(@groups) > 0} class="w-1/4">
        <.simple_form for={%{}} as={:filter} phx-change="filter">
          <.input
            type="select"
            name="group"
            value={@selected_group}
            label="Group"
            options={[{"All Groups", nil} | Enum.map(@groups, fn group -> {group, group} end)]}
          />
        </.simple_form>
      </div>

      <div :if={has_active_filters?(assigns)} class="flex items-end">
        <button phx-click="reset_filters" class="btn btn-soft">
          Reset Filters
        </button>
      </div>
    </div>
    """
  end

  defp has_active_filters?(assigns) do
    default_category =
      if assigns.categories != [], do: List.first(assigns.categories).name, else: nil

    assigns.selected_category != default_category ||
      assigns.selected_group != nil ||
      (assigns.search_query && String.trim(assigns.search_query) != "")
  end

  attr :search_query, :string, required: true

  def search_box(assigns) do
    ~H"""
    <div class="mb-4">
      <form phx-change="global_search" class="join w-full">
        <input
          type="text"
          name="search_query"
          value={@search_query}
          placeholder="Search for metrics across all categories..."
          phx-debounce="300"
          class="input join-item flex-1"
        />
        <button type="submit" class="btn btn-primary join-item">Search</button>
      </form>
    </div>
    """
  end

  attr :search_results, :list, required: true

  def search_results(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-300 p-4 mb-4">
      <h3 class="font-medium text-lg mb-2">Search Results</h3>
      <div class="rounded-box border border-base-300 max-h-60 overflow-auto">
        <table class="table table-zebra table-sm">
          <thead class="sticky top-0">
            <tr>
              <th>Metric</th>
              <th>Label</th>
              <th>UI Key</th>
              <th>Category</th>
              <th>Group</th>
              <th>Action</th>
            </tr>
          </thead>
          <tbody>
            <%= for result <- @search_results do %>
              <tr>
                <td>{result.metric}</td>
                <td>{result.ui_human_readable_name}</td>
                <td>{result.ui_key}</td>
                <td>{result.category_name}</td>
                <td>{result.group_name}</td>
                <td>
                  <button
                    phx-click="focus_metric"
                    phx-value-id={result.id}
                    phx-value-category={result.category_name}
                    phx-value-group={if result.group_name, do: result.group_name, else: ""}
                    class="link link-primary"
                  >
                    Focus
                  </button>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  attr :filtered_metrics, :list, required: true
  attr :highlighted_metric_id, :integer, default: nil

  def metrics_table(assigns) do
    ~H"""
    <div class="rounded-box border border-base-300 overflow-x-auto">
      <table class="table table-zebra table-sm">
        <thead>
          <tr>
            <th>Order</th>
            <th>Metric</th>
            <th>Label</th>
            <th>UI Key</th>
            <th>Category</th>
            <th>Group</th>
            <th>Style</th>
            <th>Format</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody id="metrics" phx-hook="Sortable">
          <.metric_row
            :for={{metric, index} <- Enum.with_index(@filtered_metrics)}
            metric={metric}
            index={index}
            total_count={length(@filtered_metrics)}
            highlighted={@highlighted_metric_id && @highlighted_metric_id == metric.id}
          />
        </tbody>
      </table>
    </div>
    """
  end

  attr :metric, :map, required: true
  attr :index, :integer, required: true
  attr :total_count, :integer, required: true
  attr :highlighted, :boolean, default: false

  def metric_row(assigns) do
    ~H"""
    <tr id={"metric-#{@metric.id}"} data-id={@metric.id} class={[@highlighted && "bg-warning/20"]}>
      <td>
        <div class="flex items-center gap-1">
          <button
            phx-click="move-up"
            phx-value-metric_id={@metric.id}
            class="btn btn-xs btn-ghost btn-circle"
            disabled={@index == 0}
          >
            <.icon name="hero-arrow-up" class="size-4" />
          </button>
          <span>{@metric.display_order}</span>
          <button
            phx-click="move-down"
            phx-value-metric_id={@metric.id}
            class="btn btn-xs btn-ghost btn-circle"
            disabled={@index == @total_count - 1}
          >
            <.icon name="hero-arrow-down" class="size-4" />
          </button>
        </div>
      </td>
      <td>
        {@metric.metric}
        <span :if={@metric.is_new} class="badge badge-xs badge-success ml-2">NEW</span>
      </td>
      <td>{@metric.ui_human_readable_name}</td>
      <td>{@metric.ui_key}</td>
      <td>{@metric.category_name}</td>
      <td>{@metric.group_name}</td>
      <td>{@metric.chart_style}</td>
      <td>{@metric.unit}</td>
      <td>
        <.metric_actions metric={@metric} />
      </td>
    </tr>
    """
  end

  @impl true
  def handle_event("filter", %{"category" => category}, socket) do
    {:noreply,
     socket
     |> assign(selected_category: category, selected_group: nil)
     |> push_patch(to: ~p"/admin/metric_registry/display_order?category=#{category}")}
  end

  def handle_event("filter", %{"group" => group}, socket) do
    {:noreply,
     socket
     |> assign(selected_group: group)
     |> push_patch(
       to:
         ~p"/admin/metric_registry/display_order?category=#{socket.assigns.selected_category}&group=#{group}"
     )}
  end

  def handle_event("move-up", params, socket) do
    metric_id = params["metric_id"] || params["metric-id"]

    metrics = socket.assigns.filtered_metrics
    {id, _} = Integer.parse(metric_id)
    index = Enum.find_index(metrics, &(&1.id == id))

    if index > 0 do
      metrics =
        List.update_at(metrics, index - 1, fn prev_metric ->
          {:ok, updated} = DisplayOrder.increment_display_order(prev_metric.id)
          %{prev_metric | display_order: updated.display_order}
        end)

      metrics =
        List.update_at(metrics, index, fn current_metric ->
          {:ok, updated} = DisplayOrder.decrement_display_order(current_metric.id)
          %{current_metric | display_order: updated.display_order}
        end)

      metrics = Enum.sort_by(metrics, & &1.display_order)

      {:noreply, assign(socket, filtered_metrics: metrics)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("move-down", params, socket) do
    metric_id = params["metric_id"] || params["metric-id"]

    metrics = socket.assigns.filtered_metrics
    {id, _} = Integer.parse(metric_id)
    index = Enum.find_index(metrics, &(&1.id == id))

    if index < length(metrics) - 1 do
      metrics =
        List.update_at(metrics, index + 1, fn next_metric ->
          {:ok, updated} = DisplayOrder.decrement_display_order(next_metric.id)
          %{next_metric | display_order: updated.display_order}
        end)

      metrics =
        List.update_at(metrics, index, fn current_metric ->
          {:ok, updated} = DisplayOrder.increment_display_order(current_metric.id)
          %{current_metric | display_order: updated.display_order}
        end)

      metrics = Enum.sort_by(metrics, & &1.display_order)

      {:noreply, assign(socket, filtered_metrics: metrics)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("reorder", %{"ids" => ids}, socket) do
    alias Sanbase.Metric.UIMetadata.DisplayOrder.Reorder

    case Reorder.prepare_reordering(ids, socket.assigns.metrics) do
      {:ok, category_id, new_order} ->
        case Reorder.apply_reordering(category_id, new_order) do
          {:ok, :ok} ->
            ordered_data = Sanbase.Metric.UIMetadata.DisplayOrder.get_ordered_metrics()
            metrics = ordered_data.metrics

            {:noreply,
             socket
             |> assign(:metrics, metrics)
             |> filter_metrics()}

          {:error, error} ->
            {:noreply,
             socket |> put_flash(:error, "Failed to reorder metrics: #{inspect(error)}")}
        end

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, reason)}
    end
  end

  @impl true
  def handle_event("delete_metric", %{"id" => id}, socket) do
    {id, _} = Integer.parse(id)

    case DisplayOrder.by_id(id) do
      nil ->
        {:noreply, socket |> put_flash(:error, "Metric not found")}

      display_order ->
        case DisplayOrder.delete(display_order) do
          {:ok, _} ->
            ordered_data = DisplayOrder.get_ordered_metrics()
            metrics = ordered_data.metrics

            {:noreply,
             socket
             |> put_flash(:info, "Metric display order deleted successfully")
             |> assign(metrics: metrics)
             |> filter_metrics()}

          {:error, changeset} ->
            {:noreply,
             socket
             |> put_flash(:error, "Error deleting metric: #{inspect(changeset.errors)}")}
        end
    end
  end

  @impl true
  def handle_event("global_search", %{"search_query" => query}, socket) do
    if String.length(query) >= 2 do
      search_results =
        socket.assigns.metrics
        |> Enum.filter(fn metric ->
          downcased_query = String.downcase(query)

          String.contains?(String.downcase(metric.metric || ""), downcased_query) ||
            String.contains?(
              String.downcase(metric.ui_human_readable_name || ""),
              downcased_query
            ) ||
            String.contains?(
              String.downcase(metric.ui_key || ""),
              downcased_query
            )
        end)
        |> Enum.take(20)

      {:noreply, assign(socket, search_query: query, search_results: search_results)}
    else
      {:noreply, assign(socket, search_query: query, search_results: [])}
    end
  end

  @impl true
  def handle_event("focus_metric", %{"id" => id, "category" => category} = params, socket) do
    {id, _} = Integer.parse(id)

    group = params["group"]

    target_url =
      if group && group != "" do
        ~p"/admin/metric_registry/display_order?category=#{category}&group=#{group}&highlight_metric=#{id}"
      else
        ~p"/admin/metric_registry/display_order?category=#{category}&highlight_metric=#{id}"
      end

    {:noreply, push_patch(socket, to: target_url)}
  end

  @impl true
  def handle_event("reset_filters", _params, socket) do
    first_category_name =
      if socket.assigns.categories != [],
        do: List.first(socket.assigns.categories).name,
        else: nil

    {:noreply,
     socket
     |> assign(
       selected_category: first_category_name,
       selected_group: nil,
       search_query: "",
       search_results: []
     )
     |> push_patch(to: ~p"/admin/metric_registry/display_order")}
  end

  defp filter_metrics(socket) do
    %{metrics: metrics, selected_category: category, selected_group: group} = socket.assigns

    filtered_metrics =
      metrics
      |> Enum.filter(&(&1.category_name == category))

    groups =
      filtered_metrics
      |> Enum.map(& &1.group_name)
      |> Enum.reject(fn group_name -> is_nil(group_name) or "" == group_name end)
      |> Enum.uniq()
      |> Enum.sort()

    filtered_metrics =
      if group && group != "" do
        Enum.filter(filtered_metrics, &(&1.group_name == group))
      else
        filtered_metrics
      end

    filtered_metrics = Enum.sort_by(filtered_metrics, & &1.display_order)

    assign(socket, filtered_metrics: filtered_metrics, groups: groups)
  end

  attr :metric, :map, required: true

  def metric_actions(assigns) do
    ~H"""
    <div class="flex space-x-3">
      <.link
        navigate={~p"/admin/metric_registry/display_order/show/#{@metric.id}"}
        class="link link-primary text-sm"
      >
        Show
      </.link>
      <.link
        navigate={~p"/admin/metric_registry/display_order/edit/#{@metric.id}"}
        class="link link-success text-sm"
      >
        Edit
      </.link>
      <.link
        phx-click="delete_metric"
        phx-value-id={@metric.id}
        data-confirm="Are you sure you want to delete this metric display order? This action cannot be undone."
        class="link link-error text-sm cursor-pointer"
      >
        Delete
      </.link>
    </div>
    """
  end
end
