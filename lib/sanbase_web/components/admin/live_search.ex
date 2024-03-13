defmodule SanbaseWeb.LiveSearch do
  use SanbaseWeb, :live_view
  import SanbaseWeb.CoreComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:query, "")
     |> assign(:routes, [])
     |> assign(:show_icon, true), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="relative m-3">
        <div class="absolute inset-y-0 start-0 flex items-center ps-3 pointer-events-none">
          <.icon name="hero-magnifying-glass" />
        </div>
        <input
          value={@query}
          phx-keyup="do-search"
          phx-debounce="200"
          type="text"
          id="search-input"
          class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg block w-full ps-10 p-2.5 "
          placeholder="Type / to search"
          phx-hook="FocusInput"
          phx-click={JS.remove_class("hidden", to: "#search-result-suggestions")}
          phx-click-away={JS.add_class("hidden", to: "#search-result-suggestions")}
          required
        />
      </div>
      <ul
        :if={@routes != []}
        id="search-result-suggestions"
        x-transition
        class="absolute z-20 ml-2 py-2 min-w-96 text-gray-700 border shadow-xl bg-gray-50 rounded-lg"
        aria-labelledby="dropdownDefaultButton"
      >
        <li :for={{name, path} <- @routes}>
          <a href={path} class="block p-4 hover:bg-gray-100 text-sm font-semibold">
            <%= name %>
          </a>
        </li>
      </ul>
    </div>
    """
  end

  @impl true
  def handle_event("do-search", %{"value" => query}, socket) do
    query = String.downcase(query)
    {:noreply, assign(socket, routes: search_routes(query), query: String.downcase(query))}
  end

  def search_routes("") do
    []
  end

  def search_routes(query) do
    SanbaseWeb.GenericAdminController.all_routes()
    |> Enum.map(fn {name, _path} = tuple ->
      name = String.downcase(name)
      query = String.downcase(query)

      similarity = FuzzyCompare.similarity(query, name)
      {tuple, similarity}
    end)
    |> Enum.filter(fn {_, similarity} -> similarity > 0.9 end)
    |> Enum.sort_by(fn {_, similarity} -> similarity end, :desc)
    |> Enum.map(fn {result, _similarity} -> result end)
  end
end
