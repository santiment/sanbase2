defmodule SanbaseWeb.SuggestEcosystemLabelsChangeLive do
  use SanbaseWeb, :live_view
  alias SanbaseWeb.UserFormsComponents

  @impl true
  def mount(_params, _session, socket) do
    # Loads only id, name, ticker, slug and ecosystems
    opts = [preload?: true, preload: [:ecosystems]]
    projects = Sanbase.Project.List.projects_base_info_only(opts)
    # TODO: Do not call repo
    ecosystems = Sanbase.Repo.all(Sanbase.Ecosystem)

    {:ok,
     socket
     |> assign(
       page_title: "Suggest asset ecosystems changes",
       projects: projects,
       selected_project: nil,
       stored_project_ecosystems: [],
       new_project_ecosystems: [],
       removed_project_ecosystems: [],
       notes: "",
       search_result: projects,
       ecosystems: ecosystems
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      case Map.get(params, "selected_project") do
        nil ->
          socket

        slug ->
          case Enum.find(socket.assigns.projects, &(&1.slug == slug)) do
            nil ->
              socket
              |> put_flash(:error, "Project not found")

            project ->
              stored_ecosystems = project.ecosystems

              socket
              |> assign(
                selected_project: project,
                stored_project_ecosystems: stored_ecosystems,
                new_project_ecosystems: [],
                removed_project_ecosystems: [],
                ecosystems: order_ecosystems(socket.assigns.ecosystems, stored_ecosystems)
              )
          end
      end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="border border-gray-100 mx-auto max-w-3xl p-6 rounded-xl shadow-sm min-h-96">
      <h1 class="text-2xl mb-6">Update the ecosystem labels of an asset</h1>

      <.select_project search_result={@search_result} />

      <div :if={@selected_project}>
        <.selected_project_details
          selected_project={@selected_project}
          new_project_ecosystems={@new_project_ecosystems}
          removed_project_ecosystems={@removed_project_ecosystems}
        />

        <h2 class="text-lg mt-10">Edit the ecosystems of the asset</h2>
        <p class="text-sm text-gray-600">
          The currently stored ecosystems are preselected. Deselect ecosystems to suggest removing them and select new ecosystems to suggest adding them.
        </p>
        <.checkbox_select_ecosystems
          ecosystems={@ecosystems}
          selected_project={@selected_project}
          stored_project_ecosystems={@stored_project_ecosystems}
        />

        <.notes_textarea />

        <.submit_suggestions_button
          text="Submit Suggestion"
          phx-submit="submit_suggestions"
          new_project_ecosystems={@new_project_ecosystems}
          removed_project_ecosystems={@removed_project_ecosystems}
          notes={@notes}
        />
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("search_project", %{"value" => search}, socket) do
    search = search |> String.downcase() |> String.trim()

    search_result =
      case search do
        "" ->
          socket.assigns.projects

        _ ->
          Enum.filter(socket.assigns.projects, fn p ->
            String.downcase(p.name) =~ search or String.downcase(p.ticker) =~ search or
              String.downcase(p.slug) =~ search
          end)
          |> Enum.sort_by(
            fn p -> String.jaro_distance(String.downcase(p.name), search) end,
            :desc
          )
      end

    {:noreply, assign(socket, search_result: search_result)}
  end

  def handle_event("update_selected_ecosystems", params, socket) do
    stored = socket.assigns.stored_project_ecosystems |> Enum.map(& &1.ecosystem)
    new = socket.assigns.new_project_ecosystems
    removed = socket.assigns.removed_project_ecosystems

    {new, removed} =
      case params do
        %{"value" => "on", "ecosystem" => e} ->
          new =
            case e in stored do
              # Append to the back so it looks better in the UI
              false -> (new ++ [e]) |> Enum.uniq()
              true -> new
            end

          removed = removed -- [e]
          {new, removed}

        %{"ecosystem" => e} ->
          new = new -- [e]

          removed =
            case e in stored do
              true -> (removed ++ [e]) |> Enum.uniq()
              false -> removed
            end

          {new, removed}
      end

    {:noreply,
     assign(socket,
       new_project_ecosystems: new,
       removed_project_ecosystems: removed
     )}
  end

  def handle_event("update_notes", %{"notes" => notes}, socket) do
    {:noreply, assign(socket, notes: notes)}
  end

  def handle_event("submit_suggestions", _params, socket) do
    attrs = %{
      project_id: socket.assigns.selected_project.id,
      added_ecosystems: socket.assigns.new_project_ecosystems || [],
      removed_ecosystems: socket.assigns.removed_project_ecosystems || [],
      notes: socket.assigns.notes
    }

    case Sanbase.Ecosystem.ChangeSuggestion.create(attrs) do
      {:ok, _} ->
        socket =
          socket
          |> assign(
            selected_project: nil,
            added_ecosystems: [],
            removed_ecosystems: [],
            notes: ""
          )
          |> put_flash(:info, "Suggestions successfully submitted!")

        {:noreply, socket}

      {:error, changeset} ->
        errors = Sanbase.Utils.ErrorHandling.changeset_errors_string(changeset)

        socket =
          socket
          |> put_flash(:error, "Error submitting suggestions. Reason: #{errors}")

        {:noreply, socket}
    end
  end

  defp order_ecosystems(ecosystems, stored) do
    stored = Enum.map(stored, & &1.ecosystem)

    ecosystems
    |> Enum.sort(:asc)
    |> Enum.sort_by(fn e -> if e.ecosystem in stored, do: 1, else: 2 end, :asc)
  end

  def select_project(assigns) do
    ~H"""
    <form class="max-w-3xl">
      <label for="default-search" class="text-sm font-medium text-gray-900 sr-only">
        Select an asset
      </label>
      <div class="relative">
        <div class="absolute inset-y-0 start-0 flex items-center ps-3 pointer-events-none">
          <.icon name="hero-magnifying-glass" class="text-gray-600" />
        </div>
        <input
          type="search"
          id="default-search"
          class="w-full p-4 ps-10 outline-none text-sm text-gray-900 border border-gray-300 rounded-lg bg-gray-50"
          placeholder="Select an asset"
          phx-keyup="search_project"
          phx-debounce="50"
          phx-click={JS.remove_class("hidden", to: "#search-result-suggestions")}
          autocomplete="off"
          required
        />
        <div
          id="search-result-suggestions"
          phx-click-away={JS.add_class("hidden", to: "#search-result-suggestions")}
          phx-key={JS.add_class("hidden", to: "#search-result-suggestions")}
          phx-click={JS.remove_class("hidden", to: "#search-result-suggestions")}
          class="hidden absolute bg-white mt-1 w-full"
        >
          <ul class="relative z-20 justify-between min-w-96 text-sm max-h-96 overflow-y-scroll scroll-bar-custom bg-white border border-gray-200 rounded-md">
            <li class="flex flex-row justify-between text-gray-600 sticky top-0 bg-white px-3 py-2 rounded-md">
              <span>Asset</span>
              <span>Ecosystems</span>
            </li>
            <li :for={project <- @search_result} class="mx-2 last:pb-4">
              <.link
                phx-click={JS.add_class("hidden", to: "#search-result-suggestions")}
                patch={~p"/forms/suggest_ecosystems?selected_project=#{project.slug}"}
                class="block p-3 hover:bg-gray-200 rounded-xl"
              >
                <.project_info project={project} />
              </.link>
            </li>
          </ul>
        </div>
      </div>
    </form>
    """
  end

  def selected_project_details(assigns) do
    ~H"""
    <div class="mt-10 min-h-48 ">
      <div class="border border-gray-100 rounded-sm px-8 py-4">
        <span class="flex flex-col  md:flex-row text-xl items-center">
          Selected Asset: <img src={@selected_project.logo_url} class="m-2 size-7" />
          <.link
            href={SanbaseWeb.Endpoint.project_url(@selected_project.slug)}
            class="text-blue-800 underline"
            target="_blank"
          >
            <%= @selected_project.name %> (#<%= @selected_project.ticker %>)
          </.link>
        </span>
        <div class="flex flex-col mt-2">
          <div>
            <span class="text-lg leading-4">Current Ecosystems:</span>
            <UserFormsComponents.ecosystems_group
              ecosystems={@selected_project.ecosystems |> Enum.map(& &1.ecosystem)}
              ecosystem_colors_class="bg-blue-100 text-blue-800"
            />
          </div>
        </div>
      </div>
      <div :if={@new_project_ecosystems != []} class="px-8 py-4 border border-gray-100 rounded-sm">
        <span class="text-lg">Added Ecosystems:</span>
        <UserFormsComponents.ecosystems_group
          ecosystems={@new_project_ecosystems}
          ecosystem_colors_class="bg-green-100 text-green-800"
        />
      </div>
      <div :if={@removed_project_ecosystems != []} class="px-8 py-4 border border-gray-100 rounded-sm">
        <span class="text-lg">Removed Ecosystems:</span>
        <UserFormsComponents.ecosystems_group
          ecosystems={@removed_project_ecosystems}
          ecosystem_colors_class="bg-red-100 text-red-800"
        />
      </div>
    </div>
    """
  end

  def checkbox_select_ecosystems(assigns) do
    ~H"""
    <div x-data="{
      search: '',
      selected: [],
      show_item(el) {
        return this.search === '' || el.textContent.includes(this.search)
      }
    }">
      <!-- Dropdown menu -->
      <div id="dropdownSearch" class="z-10 border border-gray-100 rounded-sm">
        <div class="p-3">
          <label for="input-group-search" class="sr-only">Search</label>
          <div>
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
        </div>
        <ul
          class="h-48 px-3 pb-3 overflow-y-auto text-sm text-gray-700"
          aria-labelledby="dropdownSearchButton"
        >
          <!-- li element that is shown if the search text is matching it -->
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3">
            <li :for={ecosystem <- @ecosystems} x-show="show_item($el)">
              <input
                id={"checkbox-item-#{ecosystem.id}"}
                type="checkbox"
                checked={project_ecosystem?(@selected_project, ecosystem)}
                name={ecosystem.ecosystem}
                phx-value-ecosystem={ecosystem.ecosystem}
                phx-click="update_selected_ecosystems"
                class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded"
              />
              <label
                for={"checkbox-item-#{ecosystem.id}"}
                class="w-full ms-2 text-sm font-medium text-gray-900 rounded"
              >
                <%= ecosystem.ecosystem %>
              </label>
            </li>
          </div>
        </ul>
      </div>
    </div>
    """
  end

  attr(:ecosystem, :map, required: true)
  attr(:class, :string, required: false, default: nil)

  def ecosystem_span(assigns) do
    ~H"""
    <span class={[
      "text-md font-medium me-2 px-2.5 py-1 rounded",
      @class
    ]}>
      <%= @ecosystem %>
    </span>
    """
  end

  def project_info(assigns) do
    ecosystems = Enum.map(assigns.project.ecosystems, & &1.ecosystem)
    ecosystems_len = length(ecosystems)

    ecosystems_string =
      cond do
        ecosystems_len == 0 ->
          "none"

        ecosystems_len <= 3 ->
          Enum.join(ecosystems, ", ")

        true ->
          [e1, e2 | rest] = ecosystems
          "#{e1}, #{e2} and #{length(rest)} more"
      end

    assigns = assign(assigns, :ecosystems_string, ecosystems_string)

    ~H"""
    <div class="flex flex-row items-start justify-between">
      <div>
        <span><%= @project.name %></span>
        <span class="ml-4 text-gray-500"><%= @project.ticker %></span>
      </div>
      <span class="text-gray-500"><%= @ecosystems_string %></span>
    </div>
    """
  end

  attr(:text, :string, required: true)
  attr(:notes, :string, required: true)
  attr(:new_project_ecosystems, :list, required: true)
  attr(:removed_project_ecosystems, :list, required: true)
  attr(:rest, :global, doc: "the arbitrary HTML attributes to add to the flash container")

  def submit_suggestions_button(assigns) do
    is_disabled =
      assigns.new_project_ecosystems == [] and assigns.removed_project_ecosystems == [] and
        assigns.notes == ""

    assigns = assign(assigns, :is_disabled, is_disabled)

    ~H"""
    <button
      phx-click="submit_suggestions"
      type="submit"
      class="text-white bg-blue-700 hover:bg-blue-800 font-medium rounded-lg text-sm px-4 py-2 mt-4 disabled:bg-slate-500 disabled:cursor-not-allowed"
      disabled={@is_disabled}
      title={
        if @is_disabled,
          do:
            "You need to propose changes to the ecosystems or leave a note in order to submit your proposal"
      }
      {@rest}
    >
      <%= @text %>
    </button>
    """
  end

  def notes_textarea(assigns) do
    ~H"""
    <form phx-change="update_notes">
      <textarea
        name="notes"
        rows="4"
        class="block my-3 p-2.5 w-full text-sm text-gray-900 bg-gray-50 rounded-lg border border-gray-300"
        placeholder="Tell us why these changes are proposed. You can share links, or just leave some comments."
        phx-debounce="1000"
      ></textarea>
    </form>
    """
  end

  defp project_ecosystem?(project, ecosystem) do
    Enum.any?(project.ecosystems, fn pe -> pe.id == ecosystem.id end)
  end
end
