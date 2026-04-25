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
    <div class="relative">
      <label class="input input-sm w-full">
        <.icon name="hero-magnifying-glass" class="size-4 opacity-60" />
        <input
          type="text"
          id="search-input"
          value={@query}
          phx-keyup="do-search"
          phx-debounce="200"
          phx-hook="FocusInput"
          phx-click={JS.remove_class("hidden", to: "#search-result-suggestions")}
          phx-click-away={JS.add_class("hidden", to: "#search-result-suggestions")}
          placeholder="Type / to search"
          required
        />
      </label>
      <ul
        :if={@routes != []}
        id="search-result-suggestions"
        class="menu fixed top-14 left-3 w-72 max-h-[70vh] overflow-y-auto overflow-x-hidden z-50 bg-base-100 border border-base-300 rounded-box shadow-xl flex-nowrap"
      >
        <li :for={{name, path} <- @routes} class="w-full">
          <a href={path} title={name} class="!block truncate w-full">
            {name}
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
