defmodule SanbaseWeb.MetricDisplayOrderFormLive do
  use SanbaseWeb, :live_view

  import SanbaseWeb.CoreComponents
  alias Sanbase.Metric.UIMetadata.DisplayOrder
  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(%{"metric_id" => metric_id}, _session, socket) do
    case fetch_display_order(metric_id) do
      {:error, message} ->
        {:ok,
         socket
         |> put_flash(:error, message)
         |> push_navigate(to: ~p"/admin/metric_registry/display_order")}

      {:ok, display_order} ->
        form_data = prepare_form_data(display_order)

        {:ok,
         socket
         |> assign(
           page_title: "Edit Metric Display Order | #{display_order.metric}",
           display_order: display_order,
           form: form_data.form,
           categories: form_data.categories,
           groups_by_category: form_data.groups_by_category,
           groups_for_category: form_data.groups_for_category,
           styles: form_data.styles,
           formats: form_data.formats
         )}
    end
  end

  # Fetch the display order record for the given metric ID
  defp fetch_display_order(metric_id) do
    case DisplayOrder.by_id(String.to_integer(metric_id)) do
      nil -> {:error, "Metric not found"}
      display_order -> {:ok, display_order}
    end
  end

  # Prepare all the data needed for the form
  defp prepare_form_data(display_order) do
    # Get all categories and groups from the structured data
    categories_and_groups = DisplayOrder.get_categories_and_groups()
    categories = categories_and_groups.categories
    groups_by_category = categories_and_groups.groups_by_category

    # Get groups for the current category
    groups_for_category = Map.get(groups_by_category, display_order.category_id, [])

    # Get available styles and formats
    styles = DisplayOrder.get_available_chart_styles()
    formats = DisplayOrder.get_available_formats()

    # Get category and group names for display
    category_name = if display_order.category, do: display_order.category.name, else: nil
    group_name = if display_order.group, do: display_order.group.name, else: nil

    # Create the form
    form = create_form(display_order, category_name, group_name)

    %{
      form: form,
      categories: categories,
      groups_by_category: groups_by_category,
      groups_for_category: groups_for_category,
      styles: styles,
      formats: formats
    }
  end

  # Create a form with the display order data
  defp create_form(display_order, category_name, group_name) do
    to_form(%{
      "ui_human_readable_name" => display_order.ui_human_readable_name,
      "category_id" => display_order.category_id,
      "category_name" => category_name,
      "group_id" => display_order.group_id,
      "group_name" => group_name,
      "chart_style" => display_order.chart_style,
      "unit" => display_order.unit,
      "description" => display_order.description
    })
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-full">
      <h1 class="text-blue-700 text-2xl mb-4">
        Edit Metric Display Order | {@display_order.metric}
      </h1>

      <.action_buttons display_order={@display_order} />
      <.metric_form
        form={@form}
        categories={@categories}
        groups_for_category={@groups_for_category}
        styles={@styles}
        formats={@formats}
      />
    </div>
    """
  end

  attr :display_order, :map, required: true

  def action_buttons(assigns) do
    ~H"""
    <div class="my-4">
      <AvailableMetricsComponents.available_metrics_button
        text="Back to Display Order"
        href={~p"/admin/metric_registry/display_order"}
        icon="hero-arrow-uturn-left"
      />

      <AvailableMetricsComponents.available_metrics_button
        text="View Metric"
        href={~p"/admin/metric_registry/display_order/show/#{@display_order.id}"}
        icon="hero-eye"
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

      <.input
        type="select"
        field={@form[:category_id]}
        label="Category"
        options={Enum.map(@categories, fn cat -> {cat.name, cat.id} end)}
        phx-change="category_changed"
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

      <.button phx-disable-with="Saving...">Save Changes</.button>
    </.simple_form>
    """
  end

  @impl true
  def handle_event(
        "validate",
        %{"_target" => ["category_id"], "category_id" => category_id},
        socket
      ) do
    # Parse the category_id to integer
    category_id = String.to_integer(category_id)

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
    display_order = socket.assigns.display_order

    # Parse IDs to integers
    category_id =
      if params["category_id"] && params["category_id"] != "",
        do: String.to_integer(params["category_id"]),
        else: nil

    group_id =
      if params["group_id"] && params["group_id"] != "",
        do: String.to_integer(params["group_id"]),
        else: nil

    attrs = %{
      ui_human_readable_name: params["ui_human_readable_name"],
      category_id: category_id,
      group_id: group_id,
      chart_style: params["chart_style"],
      unit: params["unit"],
      description: params["description"]
    }

    case DisplayOrder.do_update(display_order, attrs) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Metric display order updated successfully")
         |> push_navigate(to: ~p"/admin/metric_registry/display_order/show/#{display_order.id}")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Error updating metric: #{inspect(changeset.errors)}")}
    end
  end
end
