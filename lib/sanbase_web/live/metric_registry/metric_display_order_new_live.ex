defmodule SanbaseWeb.MetricDisplayOrderNewLive do
  use SanbaseWeb, :live_view

  alias Sanbase.Metric.UIMetadata.DisplayOrder
  alias Sanbase.Metric.Registry
  alias SanbaseWeb.AdminSharedComponents

  @impl true
  def mount(_params, _session, socket) do
    # Get the available categories and groups
    categories_and_groups = DisplayOrder.get_categories_and_groups()
    categories = categories_and_groups.categories
    groups_by_category = categories_and_groups.groups_by_category

    # Get initial groups for the first category (if any)
    groups_for_category =
      if categories != [] do
        first_category = List.first(categories)
        Map.get(groups_by_category, first_category.id, [])
      else
        []
      end

    # Get available styles and formats
    styles = DisplayOrder.get_available_chart_styles()
    formats = DisplayOrder.get_available_formats()

    # Get the list of metric adapter modules
    metric_modules = Sanbase.Metric.Helper.metric_modules()
    code_modules = Enum.map(metric_modules, fn cm -> inspect(cm) end)

    # Load and cache all registry metrics for searching
    registry_metrics =
      Registry.all()
      |> Registry.resolve()
      |> Enum.map(fn metric ->
        %{
          id: metric.id,
          metric: metric.metric,
          human_readable_name: metric.human_readable_name
        }
      end)

    # Create form
    form = create_form()

    {:ok,
     socket
     |> assign(
       page_title: "New Metric Display Order",
       form: form,
       categories: categories,
       groups_by_category: groups_by_category,
       groups_for_category: groups_for_category,
       styles: styles,
       formats: formats,
       code_modules: code_modules,
       source_type: "registry",
       search_query: "",
       search_results: [],
       selected_metric: nil,
       registry_metrics: registry_metrics
     )}
  end

  # Create a form with default values
  defp create_form do
    to_form(%{
      "ui_human_readable_name" => "",
      "short_label" => "",
      "ui_key" => "",
      "category_id" => "",
      "group_id" => "",
      "chart_style" => "line",
      "unit" => "",
      "description" => "",
      "metric_name" => "",
      "code_module" => "",
      "registry_metric" => ""
    })
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-full">
      <h1 class="text-primary text-2xl mb-4">New Metric Display Order</h1>

      <.action_buttons />

      <div class="card bg-base-200 border border-base-300 p-4 mb-6">
        <h2 class="text-lg font-medium mb-4">Step 1: Select Metric Source</h2>
        <div class="flex flex-wrap gap-4">
          <label class="label cursor-pointer gap-2 py-0">
            <input
              type="radio"
              name="source_type"
              value="registry"
              checked={@source_type == "registry"}
              phx-click="select_source_type"
              phx-value-type="registry"
              class="radio radio-sm radio-primary"
            />
            <span>Metric Registry</span>
          </label>
          <label class="label cursor-pointer gap-2 py-0">
            <input
              type="radio"
              name="source_type"
              value="code"
              checked={@source_type == "code"}
              phx-click="select_source_type"
              phx-value-type="code"
              class="radio radio-sm radio-primary"
            />
            <span>Code Module</span>
          </label>
        </div>

        <%= if @source_type == "registry" do %>
          <div class="mt-4">
            <h3 class="text-md font-medium mb-2">Search for a metric in the registry:</h3>
            <form phx-change="search" phx-submit="search" class="mb-4">
              <div class="join w-full">
                <input
                  type="text"
                  name="search_query"
                  value={@search_query}
                  placeholder="Search for a metric..."
                  class="input join-item flex-1"
                />
                <button type="submit" class="btn btn-primary join-item">Search</button>
              </div>
            </form>

            <%= if length(@search_results) > 0 do %>
              <div class="rounded-box border border-base-300 max-h-60 overflow-auto mb-4">
                <table class="table table-zebra table-sm">
                  <thead>
                    <tr>
                      <th>Metric</th>
                      <th>Human Readable Name</th>
                      <th>Action</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for result <- @search_results do %>
                      <tr>
                        <td class="text-sm">{result.metric}</td>
                        <td class="text-sm">{result.human_readable_name}</td>
                        <td>
                          <button
                            phx-click="select_metric"
                            phx-value-id={result.id}
                            class="link link-primary text-sm"
                          >
                            Select
                          </button>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>

            <%= if @selected_metric do %>
              <div class="alert alert-success alert-soft mb-4">
                <div>
                  <h3 class="font-medium mb-1">Selected Metric:</h3>
                  <p><strong>Name:</strong> {@selected_metric.metric}</p>
                  <p>
                    <strong>Human Readable Name:</strong> {@selected_metric.human_readable_name}
                  </p>
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
          <div class="mt-4">
            <h3 class="text-md font-medium mb-2">Enter metric details:</h3>
            <div class="grid grid-cols-1 gap-4 mb-4">
              <fieldset class="fieldset">
                <legend class="fieldset-legend">Metric Name</legend>
                <input
                  type="text"
                  name="metric_name"
                  value={@form[:metric_name].value}
                  phx-change="update_form"
                  class="input w-full"
                />
              </fieldset>
              <fieldset class="fieldset">
                <legend class="fieldset-legend">Code Module</legend>
                <select name="code_module" phx-change="update_form" class="select w-full">
                  <option value="">Select a module</option>
                  <%= for module <- @code_modules do %>
                    <option value={module} selected={@form[:code_module].value == module}>
                      {module}
                    </option>
                  <% end %>
                </select>
              </fieldset>
            </div>
          </div>
        <% end %>
      </div>

      <div class="card bg-base-200 border border-base-300 p-4">
        <h2 class="text-lg font-medium mb-4">Step 2: Add Display Information</h2>
        <.metric_form
          form={@form}
          categories={@categories}
          groups_for_category={@groups_for_category}
          styles={@styles}
          formats={@formats}
        />
      </div>
    </div>
    """
  end

  def action_buttons(assigns) do
    ~H"""
    <div class="my-4">
      <AdminSharedComponents.nav_button
        text="Back to Display Order"
        href={~p"/admin/metric_registry/display_order"}
        icon="hero-arrow-uturn-left"
      />
    </div>
    """
  end

  attr :form, :map, required: true
  attr :categories, :list, required: true
  attr :groups_for_category, :list, required: true
  attr :styles, :list, required: true
  attr :formats, :list, required: true

  def metric_form(assigns) do
    ~H"""
    <.simple_form for={@form} phx-change="validate" phx-submit="save">
      <.input type="text" field={@form[:ui_human_readable_name]} label="Label" />
      <.input type="text" field={@form[:short_label]} label="Short Label" />
      <.input
        type="text"
        field={@form[:ui_key]}
        label="UI Key"
        placeholder="e.g. daily_active_addresses"
      />

      <.input
        type="select"
        field={@form[:category_id]}
        label="Category"
        options={Enum.map(@categories, fn cat -> {cat.name, cat.id} end)}
      />

      <.input
        type="select"
        field={@form[:group_id]}
        label="Group"
        options={Enum.map(@groups_for_category, fn grp -> {grp.name, grp.id} end)}
        prompt="Select a group (optional)"
      />

      <.input type="select" field={@form[:chart_style]} label="Chart Style" options={@styles} />

      <.input type="select" field={@form[:unit]} label="Value Format" options={@formats} />

      <.input
        type="textarea"
        field={@form[:description]}
        label="Description"
        placeholder="Detailed description of what this metric measures and how it can be used"
      />

      <.button phx-disable-with="Creating...">Create Metric Display Order</.button>
    </.simple_form>
    """
  end

  @impl true
  def handle_event("select_source_type", %{"type" => type}, socket) do
    {:noreply, assign(socket, source_type: type)}
  end

  @impl true
  def handle_event("search", %{"search_query" => query}, socket) do
    if String.length(query) >= 2 do
      # Search for metrics in the cached registry metrics
      results = search_registry_metrics(socket.assigns.registry_metrics, query)
      {:noreply, assign(socket, search_query: query, search_results: results)}
    else
      {:noreply, assign(socket, search_query: query, search_results: [])}
    end
  end

  @impl true
  def handle_event("select_metric", %{"id" => id}, socket) do
    id = String.to_integer(id)

    # Find the metric in our cached registry metrics
    metric = Enum.find(socket.assigns.registry_metrics, fn m -> m.id == id end)

    if metric do
      # Update the form with the metric information
      form =
        socket.assigns.form
        |> Map.put(
          :source,
          to_form(%{
            "ui_human_readable_name" => metric.human_readable_name,
            "ui_key" => "",
            "metric_name" => metric.metric,
            "registry_metric" => metric.metric
          })
        )

      {:noreply,
       socket
       |> assign(
         selected_metric: metric,
         form: form
       )}
    else
      {:noreply, socket |> put_flash(:error, "Selected metric not found")}
    end
  end

  @impl true
  def handle_event("update_form", params, socket) do
    form =
      socket.assigns.form
      |> Map.put(:source, to_form(params))

    {:noreply, assign(socket, form: form)}
  end

  @impl true
  def handle_event(
        "validate",
        %{"_target" => ["category_id"], "category_id" => category_id},
        socket
      ) do
    # Parse the category_id to integer
    {category_id, _} = Integer.parse(category_id)

    # Get the groups for the selected category
    groups = Map.get(socket.assigns.groups_by_category, category_id, [])

    {:noreply, assign(socket, groups_for_category: groups)}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save", params, socket) do
    # Parse IDs to integers
    category_id =
      if params["category_id"] && params["category_id"] != "",
        do: String.to_integer(params["category_id"]),
        else: nil

    group_id =
      if params["group_id"] && params["group_id"] != "",
        do: String.to_integer(params["group_id"]),
        else: nil

    # Add metric-specific parameters based on source type
    result =
      case socket.assigns.source_type do
        "registry" ->
          if socket.assigns.selected_metric do
            metric = socket.assigns.selected_metric

            DisplayOrder.add_metric(
              metric.metric,
              category_id,
              group_id,
              ui_human_readable_name: params["ui_human_readable_name"],
              short_label: params["short_label"],
              ui_key: params["ui_key"],
              chart_style: params["chart_style"],
              unit: params["unit"],
              description: params["description"],
              source_type: "registry",
              metric_registry_id: metric.id,
              registry_metric: metric.metric
            )
          else
            {:error, "No metric selected"}
          end

        "code" ->
          if params["metric_name"] && params["metric_name"] != "" &&
               params["code_module"] && params["code_module"] != "" do
            metric_name = params["metric_name"]
            code_module = params["code_module"]

            DisplayOrder.add_metric(
              metric_name,
              category_id,
              group_id,
              ui_human_readable_name: params["ui_human_readable_name"],
              short_label: params["short_label"],
              ui_key: params["ui_key"],
              chart_style: params["chart_style"],
              unit: params["unit"],
              description: params["description"],
              source_type: "code",
              code_module: code_module
            )
          else
            {:error, "Metric name and code module are required"}
          end
      end

    case result do
      {:ok, display_order} ->
        {:noreply,
         socket
         |> put_flash(:info, "Metric display order created successfully")
         |> push_navigate(to: ~p"/admin/metric_registry/display_order/show/#{display_order.id}")}

      {:error, changeset} when is_struct(changeset) ->
        {:noreply,
         socket
         |> put_flash(:error, "Error creating metric: #{inspect(changeset.errors)}")}

      {:error, message} when is_binary(message) ->
        {:noreply,
         socket
         |> put_flash(:error, message)}
    end
  end

  # Search through cached registry metrics with case-insensitive matching
  defp search_registry_metrics(registry_metrics, query) do
    downcased_query = String.downcase(query)

    registry_metrics
    |> Enum.filter(fn metric ->
      String.contains?(String.downcase(metric.metric), downcased_query) ||
        String.contains?(String.downcase(metric.human_readable_name || ""), downcased_query)
    end)
    # Limit results to prevent overwhelming the UI
    |> Enum.take(20)
  end
end
