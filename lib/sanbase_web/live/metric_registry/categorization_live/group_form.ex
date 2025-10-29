defmodule SanbaseWeb.Categorization.GroupLive.Form do
  use SanbaseWeb, :live_view

  import SanbaseWeb.CoreComponents
  alias Sanbase.Metric.Category
  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(_params, _session, socket) do
    categories = Category.list_categories_with_groups()

    socket =
      socket
      |> assign(categories: categories)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, params) do
    # If category_id is provided in the URL, pre-select it
    category_id = params["category_id"] && String.to_integer(params["category_id"])

    socket
    |> assign(
      page_title: "Create New Group",
      group: %Category.MetricGroup{category_id: category_id},
      action: :new
    )
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    case Category.get_group(String.to_integer(id)) do
      {:ok, group} ->
        socket
        |> assign(
          page_title: "Edit Group",
          group: group,
          action: :edit
        )

      _ ->
        socket
        |> put_flash(:error, "Group not found")
        |> push_navigate(to: ~p"/admin/metric_registry/categorization/groups")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-full">
      <div class="text-gray-800 text-2xl mb-4">
        {if @action == :new, do: "Create New Group", else: "Edit Group"}
      </div>

      <div class="my-4">
        <AvailableMetricsComponents.available_metrics_button
          text="Back to Groups"
          href={~p"/admin/metric_registry/categorization/groups"}
          icon="hero-arrow-uturn-left"
        />
      </div>

      <.simple_form for={%{}} as={:group} phx-submit="save">
        <.input type="text" name="name" value={@group.name} label="Group Name" />

        <.input
          type="select"
          name="category_id"
          label="Category"
          value={@group.category_id}
          options={Enum.map(@categories, fn category -> {category.name, category.id} end)}
        />
        <.input
          type="text"
          name="short_description"
          value={@group.short_description}
          label="Short Description"
        />
        <.input type="textarea" name="description" value={@group.description} label="Description" />

        <.input type="number" name="display_order" value={@group.display_order} label="Display Order" />

        <.button type="submit">Save</.button>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def handle_event("save", params, socket) do
    group = socket.assigns.group

    result =
      case socket.assigns.action do
        :new -> Category.create_group(params)
        :edit -> Category.update_group(group, params)
      end

    case result do
      {:ok, _group} ->
        {:noreply,
         socket
         |> put_flash(:info, "Group saved successfully")
         |> push_navigate(to: ~p"/admin/metric_registry/categorization/groups")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, format_errors(changeset))
         |> assign(
           group: %{
             socket.assigns.group
             | name: params["name"],
               category_id: params["category_id"]
           }
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
