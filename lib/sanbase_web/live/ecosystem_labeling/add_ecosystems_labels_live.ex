defmodule SanbaseWeb.AddEcosystemLabelsLive do
  use SanbaseWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    projects = Sanbase.Project.List.projects()
    # TODO: Do not call repo
    ecosystems = Sanbase.Repo.all(Sanbase.Ecosystem)
    selected_project = Enum.find(projects, &(&1.slug == "santiment"))

    {:ok,
     socket
     |> assign(
       projects: projects,
       selected_project: selected_project,
       search_result: [],
       ecosystems: ecosystems
     )}
  end

  def handle_params(params, _url, socket) do
    socket =
      case Map.get(params, "selected_project") do
        nil ->
          socket

        slug ->
          socket
          |> assign(selected_project: Enum.find(socket.assigns.projects, &(&1.slug == slug)))
      end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="border border-red-500">
      <h1 class="text-lg mb-10">Update the Ecosystem Labels of a project</h1>

      <.select_project search_result={@search_result} />

      <div :if={@selected_project} class="mt-10">
        <h2 class="text-md"><%= @selected_project.name %>'s Ecosystems</h2>
        <ul class="mt-2">
          <li :for={ecosystem <- @selected_project.ecosystems} class="text-sm">
            <%= ecosystem.ecosystem %>
          </li>
        </ul>
      </div>

      <div :if={@selected_project}>
        <h2 class="text-md mt-10">Edit the ecosystems of the project</h2>
        <.checkbox_dropdown ecosystems={@ecosystems} selected_project={@selected_project} />
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("search_project", %{"value" => search}, socket) do
    search = String.downcase(search)

    search_result =
      case search do
        "" ->
          []

        _ ->
          Enum.filter(socket.assigns.projects, fn p ->
            String.downcase(p.name) =~ search or String.downcase(p.ticker) =~ search or
              String.downcase(p.slug) =~ search
          end)
      end

    {:noreply, assign(socket, search_result: search_result)}
  end

  def select_project(assigns) do
    ~H"""
    <form class="max-w-2xl mx-autck">
      <label for="default-search" class="mb-2 text-sm font-medium text-gray-900 sr-only">
        Select an asset
      </label>
      <div class="relative">
        <div class="absolute inset-y-0 start-0 flex items-center ps-3 pointer-events-none">
          <.icon name="hero-magnifying-glass" class="text-gray-600" />
        </div>
        <input
          type="search"
          id="default-search"
          class="block w-full p-4 ps-10 outline-none text-sm text-gray-900 border border-gray-300 rounded-lg bg-gray-50"
          placeholder="Select an asset"
          phx-keyup="search_project"
          phx-debounce="200"
          phx-click={JS.remove_class("hidden", to: "#search-result-suggestions")}
          required
        />
        <button
          type="submit"
          class="text-white absolute end-2.5 bottom-2.5 bg-blue-700 hover:bg-blue-800 font-medium rounded-lg text-sm px-4 py-2"
        >
          Search
        </button>
        <div
          :if={@search_result != []}
          id="search-result-suggestions"
          phx-click-away={JS.add_class("hidden", to: "#search-result-suggestions")}
          phx-click-
          class="absolute bg-white mt-1"
        >
          <ul class="min-w-96 border border-gray-300 rounded-xl px-2 py-2">
            <li :for={project <- @search_result}>
              <.link
                phx-click={JS.add_class("hidden", to: "#search-result-suggestions")}
                patch={~p"/admin2/add_ecosystems_labels_live?selected_project=#{project.slug}"}
                class="block p-3 hover:bg-gray-200 rounded-xl"
              >
                <%= project.name %>
              </.link>
            </li>
          </ul>
        </div>
      </div>
    </form>
    """
  end

  def checkbox_dropdown(assigns) do
    ~H"""
    <div x-data="{
      search: '',
      selected: [],
      show_item(el) {
        console.log(this.search)
        return this.search === '' || el.querySelector('div').textContent.includes(this.search)
      }
    }">
      <div class="flex flex-col md:flex-row">
        <button
          id="dropdownSearchButton"
          data-dropdown-toggle="dropdownSearch"
          class="inline-flex items-center px-4 py-2 text-sm font-medium text-center text-white bg-blue-700 rounded-lg hover:bg-blue-800 "
          type="button"
        >
          <span>Edit Ecosystems List</span>
          <.icon name="hero-chevron-down" />
        </button>
      </div>
      <!-- Dropdown menu -->
      <div id="dropdownSearch" class="z-10 hidden bg-white rounded-lg shadow w-60">
        <div class="p-3">
          <label for="input-group-search" class="sr-only">Search</label>
          <div class="relative">
            <div class="absolute inset-y-0 start-0 flex items-center ps-3 pointer-events-none text-gray-600">
              <.icon name="hero-magnifying-glass" />
            </div>
            <input
              type="text"
              id="input-group-search"
              class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg block w-full ps-10 p-2.5"
              placeholder="Search ecosystem"
              x-model="search"
            />
          </div>
        </div>
        <ul
          class="h-96 px-3 pb-3 overflow-y-auto text-sm text-gray-700"
          aria-labelledby="dropdownSearchButton"
        >
          <!-- li element that is shown if the search text is matching it -->
          <li :for={ecosystem <- @ecosystems} x-show="show_item($el)">
            <div class="flex items-center p-2 rounded hover:bg-gray-100">
              <input
                id={"checkbox-item-#{ecosystem.id}"}
                type="checkbox"
                checked={project_ecosystem?(@selected_project, ecosystem)}
                value=""
                class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded"
              />
              <label
                for={"checkbox-item-#{ecosystem.id}"}
                class="w-full ms-2 text-sm font-medium text-gray-900 rounded"
              >
                <%= ecosystem.ecosystem %>
              </label>
            </div>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  defp project_ecosystem?(project, ecosystem) do
    Enum.any?(project.ecosystems, fn pe -> pe.id == ecosystem.id end)
  end
end
