defmodule SanbaseWeb.TagLive.TagIndex do
  use SanbaseWeb, :live_view

  alias Sanbase.Metric.Tag
  alias SanbaseWeb.AdminSharedComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Manage Tags")
     |> load_data()}
  end

  defp load_data(socket) do
    assign(socket, tags: Tag.list_tags(), counts: Tag.count_mappings_per_tag())
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center w-full">
      <div class="text-2xl mb-4">
        Manage Tags
      </div>

      <.navigation />

      <div class="rounded-box border border-base-300 overflow-hidden">
        <table class="table table-sm">
          <thead>
            <tr>
              <th>Name</th>
              <th>Description</th>
              <th class="text-center">Metrics assigned</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={tag <- @tags} class="hover:bg-base-200">
              <td>
                <span class="badge badge-sm badge-secondary">{tag.name}</span>
              </td>
              <td class="text-base-content/60">{tag.description}</td>
              <td class="text-center">{Map.get(@counts, tag.id, 0)}</td>
              <td>
                <div class="flex space-x-2">
                  <.link
                    navigate={~p"/admin/metric_registry/tags/edit/#{tag.id}"}
                    class="link link-primary"
                  >
                    Edit
                  </.link>
                  <button
                    phx-click="delete"
                    phx-value-id={tag.id}
                    class="link link-error"
                    data-confirm="Delete this tag? This also removes all its metric assignments."
                  >
                    Delete
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@tags == []} class="px-6 py-12 text-center text-base-content/50">
          No tags yet.
        </div>
      </div>
    </div>
    """
  end

  def navigation(assigns) do
    ~H"""
    <div class="my-4 flex flex-row space-x-2">
      <AdminSharedComponents.nav_button
        text="Back to Tagging Dashboard"
        href={~p"/admin/metric_registry/tags"}
        icon="hero-arrow-uturn-left"
      />
      <AdminSharedComponents.nav_button
        text="Create New Tag"
        href={~p"/admin/metric_registry/tags/new"}
        icon="hero-plus"
      />
    </div>
    """
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    id = String.to_integer(id)

    case Tag.get_tag(id) do
      {:ok, tag} ->
        Tag.delete_tag(tag)

        {:noreply,
         socket
         |> put_flash(:info, "Tag deleted successfully")
         |> load_data()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Tag not found")}
    end
  end
end
