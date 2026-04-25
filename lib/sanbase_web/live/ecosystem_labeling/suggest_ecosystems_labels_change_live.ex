defmodule SanbaseWeb.SuggestEcosystemLabelsChangeLive do
  use SanbaseWeb, :live_view
  alias SanbaseWeb.UserFormsComponents
  alias SanbaseWeb.SuggestLiveHelpers

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
    <div class="card bg-base-100 border border-base-300 mx-auto max-w-3xl p-6 shadow-sm min-h-96">
      <h1 class="text-2xl mb-6">Update the ecosystem labels of an asset</h1>

      <.select_project search_result={@search_result} />

      <div :if={@selected_project}>
        <.selected_project_details
          selected_project={@selected_project}
          new_project_ecosystems={@new_project_ecosystems}
          removed_project_ecosystems={@removed_project_ecosystems}
        />

        <h2 class="text-lg mt-10">Edit the ecosystems of the asset</h2>
        <p class="text-sm text-base-content/60">
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
    search_result =
      SuggestLiveHelpers.filter_projects_by_search(socket.assigns.projects, search)

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
      <label for="default-search" class="sr-only">
        Select an asset
      </label>
      <div class="relative">
        <label class="input w-full">
          <.icon name="hero-magnifying-glass" class="text-base-content/60" />
          <input
            type="search"
            id="default-search"
            placeholder="Select an asset"
            phx-keyup="search_project"
            phx-debounce="50"
            phx-click={JS.remove_class("hidden", to: "#search-result-suggestions")}
            autocomplete="off"
            required
          />
        </label>
        <div
          id="search-result-suggestions"
          phx-click-away={JS.add_class("hidden", to: "#search-result-suggestions")}
          phx-key={JS.add_class("hidden", to: "#search-result-suggestions")}
          phx-click={JS.remove_class("hidden", to: "#search-result-suggestions")}
          class="hidden absolute mt-1 w-full z-20"
        >
          <ul class="relative bg-base-100 border border-base-300 rounded-box shadow-xl text-sm max-h-96 overflow-y-auto">
            <li class="flex flex-row justify-between text-base-content/60 sticky top-0 bg-base-100 border-b border-base-300 px-3 py-2">
              <span>Asset</span>
              <span>Ecosystems</span>
            </li>
            <li :for={project <- @search_result} class="mx-2 last:pb-4">
              <.link
                phx-click={JS.add_class("hidden", to: "#search-result-suggestions")}
                patch={~p"/forms/suggest_ecosystems?selected_project=#{project.slug}"}
                class="block p-3 hover:bg-base-200 rounded-box"
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
    <div class="mt-10 min-h-48 space-y-3">
      <div class="card bg-base-100 border border-base-300 px-8 py-4">
        <span class="flex flex-col md:flex-row text-xl items-center gap-2">
          Selected Asset: <img src={@selected_project.logo_url} class="m-2 size-7" />
          <.link
            href={SanbaseWeb.Endpoint.project_url(@selected_project.slug)}
            class="link link-primary"
            target="_blank"
          >
            {@selected_project.name} (#{@selected_project.ticker})
          </.link>
        </span>
        <div class="flex flex-col mt-2">
          <div>
            <span class="text-lg leading-4">Current Ecosystems:</span>
            <UserFormsComponents.ecosystems_group
              ecosystems={@selected_project.ecosystems |> Enum.map(& &1.ecosystem)}
              ecosystem_colors_class="badge-info"
            />
          </div>
        </div>
      </div>
      <div
        :if={@new_project_ecosystems != []}
        class="card bg-base-100 border border-base-300 px-8 py-4"
      >
        <span class="text-lg">Added Ecosystems:</span>
        <UserFormsComponents.ecosystems_group
          ecosystems={@new_project_ecosystems}
          ecosystem_colors_class="badge-success"
        />
      </div>
      <div
        :if={@removed_project_ecosystems != []}
        class="card bg-base-100 border border-base-300 px-8 py-4"
      >
        <span class="text-lg">Removed Ecosystems:</span>
        <UserFormsComponents.ecosystems_group
          ecosystems={@removed_project_ecosystems}
          ecosystem_colors_class="badge-error"
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
      <div id="dropdownSearch" class="card bg-base-100 border border-base-300">
        <div class="p-3">
          <label for="input-group-search" class="sr-only">Search</label>
          <label class="input w-full">
            <.icon name="hero-magnifying-glass" class="text-base-content/60" />
            <input
              type="text"
              id="input-group-search"
              placeholder="Search ecosystem"
              x-model="search"
            />
          </label>
        </div>
        <ul
          class="h-48 px-3 pb-3 overflow-y-auto text-sm"
          aria-labelledby="dropdownSearchButton"
        >
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-2">
            <li :for={ecosystem <- @ecosystems} x-show="show_item($el)">
              <label class="label cursor-pointer justify-start gap-2">
                <input
                  id={"checkbox-item-#{ecosystem.id}"}
                  type="checkbox"
                  checked={project_ecosystem?(@selected_project, ecosystem)}
                  name={ecosystem.ecosystem}
                  phx-value-ecosystem={ecosystem.ecosystem}
                  phx-click="update_selected_ecosystems"
                  class="checkbox checkbox-sm checkbox-primary"
                />
                <span class="text-sm font-medium">{ecosystem.ecosystem}</span>
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
    <span class={["badge badge-soft", @class]}>
      {@ecosystem}
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
        <span>{@project.name}</span>
        <span class="ml-4 text-base-content/60">{@project.ticker}</span>
      </div>
      <span class="text-base-content/60">{@ecosystems_string}</span>
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
      class="btn btn-primary mt-4"
      disabled={@is_disabled}
      title={
        if @is_disabled,
          do:
            "You need to propose changes to the ecosystems or leave a note in order to submit your proposal"
      }
      {@rest}
    >
      {@text}
    </button>
    """
  end

  def notes_textarea(assigns) do
    ~H"""
    <form phx-change="update_notes">
      <textarea
        name="notes"
        rows="4"
        class="textarea w-full my-3"
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
