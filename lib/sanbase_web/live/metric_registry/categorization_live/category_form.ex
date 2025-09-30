defmodule SanbaseWeb.Categorization.CategoryLive.Form do
  use SanbaseWeb, :live_view

  import SanbaseWeb.CoreComponents
  alias Sanbase.Metric.Category
  alias Sanbase.Metric.Category.MetricCategory
  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    # For new categories, get the highest display_order and increment it by 1
    max_order =
      case Category.list_categories() do
        [] ->
          0

        categories ->
          categories
          |> Enum.map(& &1.display_order)
          |> Enum.max(fn -> 0 end)
      end

    socket
    |> assign(
      page_title: "Create New Category",
      category: %MetricCategory{display_order: max_order + 1},
      action: :new
    )
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    id = String.to_integer(id)

    case Category.get_category(id) do
      {:ok, category} ->
        socket
        |> assign(
          page_title: "Edit Category",
          category: category,
          action: :edit
        )

      _ ->
        socket
        |> put_flash(:error, "Category not found")
        |> push_navigate(to: ~p"/admin/metric_registry/categorization/categories")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-full">
      <div class="text-gray-800 text-2xl mb-4">
        {if @action == :new, do: "Create New Category", else: "Edit Category"}
      </div>

      <div class="my-4">
        <AvailableMetricsComponents.available_metrics_button
          text="Back to Categories"
          href={~p"/admin/metric_registry/categorization/categories"}
          icon="hero-arrow-uturn-left"
        />
      </div>

      <.simple_form for={%{}} as={:category} phx-submit="save">
        <.input type="text" name="name" value={@category.name} label="Category Name" />
        <.input
          type="number"
          name="display_order"
          value={@category.display_order}
          label="Display Order"
        />

        <.button type="submit">Save</.button>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def handle_event("save", params, socket) do
    %{"name" => name, "display_order" => display_order} = params
    display_order = String.to_integer(display_order)
    category = socket.assigns.category

    attrs = %{
      name: name,
      display_order: display_order
    }

    result =
      case socket.assigns.action do
        :new -> Category.create_category(attrs)
        :edit -> Category.update_category(category, attrs)
      end

    case result do
      {:ok, _category} ->
        {:noreply,
         socket
         |> put_flash(:info, "Category saved successfully")
         |> push_navigate(to: ~p"/admin/metric_registry/categorization/categories")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, format_errors(changeset))
         |> assign(
           category: %{socket.assigns.category | name: name, display_order: display_order}
         )}
    end
  end

  defp format_errors(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _}} ->
      "#{Phoenix.Naming.humanize(field)} #{message}"
    end)
    |> Enum.join(", ")
  end
end
