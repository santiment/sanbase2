defmodule SanbaseWeb.MetricDisplayOrderFormLive do
  use SanbaseWeb, :live_view

  import SanbaseWeb.CoreComponents
  alias Sanbase.Metric.DisplayOrder
  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(%{"metric" => metric}, _session, socket) do
    case fetch_display_order(metric) do
      {:error, message} ->
        {:ok,
         socket
         |> put_flash(:error, message)
         |> push_navigate(to: ~p"/admin2/metric_registry/display_order")}

      {:ok, display_order} ->
        case validate_source_type(display_order) do
          {:error, message} ->
            {:ok,
             socket
             |> put_flash(:error, message)
             |> push_navigate(to: ~p"/admin2/metric_registry/display_order")}

          :ok ->
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
  end

  # Fetch the display order record for the given metric
  defp fetch_display_order(metric) do
    case DisplayOrder.by_metric(metric) do
      nil -> {:error, "Metric not found"}
      display_order -> {:ok, display_order}
    end
  end

  # Validate that the display order has the correct source type
  defp validate_source_type(display_order) do
    if display_order.source_type != "code" do
      {:error, "Only code-defined metrics can be edited here"}
    else
      :ok
    end
  end

  # Prepare all the data needed for the form
  defp prepare_form_data(display_order) do
    # Get all categories and groups for the form
    ordered_metrics = DisplayOrder.all_ordered()

    # Extract unique categories in the order they appear
    categories =
      ordered_metrics
      |> Enum.map(& &1.category)
      |> Enum.uniq()

    # Group metrics by category and extract unique groups in order
    groups_by_category = get_groups_by_category(ordered_metrics)

    # Get groups for the current category
    groups_for_category = Map.get(groups_by_category, display_order.category, [])

    # Get available styles and formats
    styles = DisplayOrder.get_available_chart_styles()
    formats = DisplayOrder.get_available_formats()

    # Create the form
    form = create_form(display_order)

    %{
      form: form,
      categories: categories,
      groups_by_category: groups_by_category,
      groups_for_category: groups_for_category,
      styles: styles,
      formats: formats
    }
  end

  # Extract groups by category from ordered metrics
  defp get_groups_by_category(ordered_metrics) do
    ordered_metrics
    |> Enum.group_by(& &1.category)
    |> Enum.map(fn {category, metrics} ->
      groups =
        metrics
        |> Enum.map(& &1.group)
        |> Enum.uniq()

      {category, groups}
    end)
    |> Map.new()
  end

  # Create a form with the display order data
  defp create_form(display_order) do
    to_form(%{
      "label" => display_order.label,
      "category" => display_order.category,
      "group" => display_order.group,
      "style" => display_order.style,
      "format" => display_order.format,
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
        href={~p"/admin2/metric_registry/display_order"}
        icon="hero-arrow-uturn-left"
      />

      <AvailableMetricsComponents.available_metrics_button
        text="View Metric"
        href={~p"/admin2/metric_registry/display_order/show/#{@display_order.metric}"}
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
      <.input type="text" field={@form[:label]} label="Label" />

      <.input
        type="select"
        field={@form[:category]}
        label="Category"
        options={@categories}
        phx-change="category_changed"
      />

      <.input
        type="select"
        field={@form[:group]}
        label="Group"
        options={@groups_for_category}
        prompt="Select a group (optional)"
      />

      <.input type="select" field={@form[:style]} label="Chart Style" options={@styles} />

      <.input type="select" field={@form[:format]} label="Value Format" options={@formats} />

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
  def handle_event("validate", %{"_target" => ["category"], "category" => category}, socket) do
    # Get the groups for the selected category
    groups = Map.get(socket.assigns.groups_by_category, category, [])

    {:noreply, assign(socket, groups_for_category: groups)}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save", params, socket) do
    display_order = socket.assigns.display_order

    attrs = %{
      label: params["label"],
      category: params["category"],
      group: params["group"],
      style: params["style"],
      format: params["format"],
      description: params["description"]
    }

    case DisplayOrder.update(display_order, attrs) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Metric display order updated successfully")
         |> push_navigate(
           to: ~p"/admin2/metric_registry/display_order/show/#{display_order.metric}"
         )}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Error updating metric: #{inspect(changeset.errors)}")}
    end
  end
end
