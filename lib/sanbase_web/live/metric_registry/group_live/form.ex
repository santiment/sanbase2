defmodule SanbaseWeb.GroupLive.Form do
  use SanbaseWeb, :live_view

  import SanbaseWeb.CoreComponents
  alias Sanbase.Metric.UIMetadata.Category
  alias Sanbase.Metric.UIMetadata.Group
  alias SanbaseWeb.AvailableMetricsComponents

  @impl true
  def mount(_params, _session, socket) do
    categories = Category.all_ordered()

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
    category_id =
      if params["category_id"] do
        String.to_integer(params["category_id"])
      else
        nil
      end

    socket
    |> assign(
      page_title: "Create New Group",
      group: %Group{category_id: category_id},
      action: :new
    )
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    id = String.to_integer(id)
    group = Group.by_id(id)

    if group do
      socket
      |> assign(
        page_title: "Edit Group",
        group: group,
        action: :edit
      )
    else
      socket
      |> put_flash(:error, "Group not found")
      |> push_navigate(to: ~p"/admin/metric_registry/groups")
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
          href={~p"/admin/metric_registry/groups"}
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

        <.button type="submit">Save</.button>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def handle_event("save", %{"name" => name, "category_id" => category_id}, socket) do
    category_id = String.to_integer(category_id)
    group = socket.assigns.group

    attrs = %{
      name: name,
      category_id: category_id
    }

    result =
      case socket.assigns.action do
        :new -> Group.create(attrs)
        :edit -> Group.update(group, attrs)
      end

    case result do
      {:ok, _group} ->
        {:noreply,
         socket
         |> put_flash(:info, "Group saved successfully")
         |> push_navigate(to: ~p"/admin/metric_registry/groups")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, format_errors(changeset))
         |> assign(group: %{socket.assigns.group | name: name, category_id: category_id})}
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
