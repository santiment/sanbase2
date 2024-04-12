defmodule SanbaseWeb.SuggestGithubOrganizationsLive do
  use SanbaseWeb, :live_view
  alias SanbaseWeb.UserFormsComponents

  @impl true
  def mount(_params, _session, socket) do
    # Loads only id, name, ticker, slug and github_organizations
    opts = [preload?: true, preload: [:github_organizations]]
    projects = Sanbase.Project.List.projects_base_info_only(opts)

    {:ok,
     socket
     |> assign(
       page_title: "Suggest asset Github Organizations changes",
       projects: projects,
       selected_project: nil,
       stored_project_organizations: [],
       new_project_organizations: [],
       removed_project_organizations: [],
       notes: "",
       search_result: projects
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      case Map.get(params, "selected_project") do
        nil ->
          socket

        slug ->
          project = Enum.find(socket.assigns.projects, &(&1.slug == slug))
          stored_organizations = project.github_organizations

          socket
          |> assign(
            selected_project: project,
            stored_project_organizations: stored_organizations,
            new_project_organizations: [],
            removed_project_organizations: []
          )
      end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="border border-gray-100 mx-auto max-w-3xl p-6 rounded-xl shadow-sm min-h-96">
      <h1 class="text-2xl mb-6">Update the Github Organizations of an asset</h1>

      <.select_project search_result={@search_result} />

      <div :if={@selected_project}>
        <.selected_project_details
          selected_project={@selected_project}
          new_project_organizations={@new_project_organizations}
          removed_project_organizations={@removed_project_organizations}
        />

        <h2 class="text-lg mt-10">Edit the Github Organizations of the asset</h2>
        <p class="text-sm text-gray-600">
          The currently stored github organizations are preselected. Deselect an organization to suggest removing it.
        </p>
        <.checkbox_select_organizations
          organizations={@stored_project_organizations}
          selected_project={@selected_project}
          stored_project_organizations={@stored_project_organizations}
          removed_project_organizations={@removed_project_organizations}
        />

        <.add_gitub_organization />

        <.notes_textarea />

        <.submit_suggestions_button
          text="Submit Suggestion"
          phx-submit="submit_suggestions"
          new_project_organizations={@new_project_organizations}
          removed_project_organizations={@removed_project_organizations}
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

  def handle_event("update_selected_organizations", params, socket) do
    stored = socket.assigns.stored_project_organizations |> Enum.map(& &1.organization)
    new = socket.assigns.new_project_organizations
    removed = socket.assigns.removed_project_organizations

    {new, removed} =
      case params do
        %{"value" => "on", "organization" => e} ->
          new =
            case e in stored do
              # Append to the back so it looks better in the UI
              false -> (new ++ [e]) |> Enum.uniq()
              true -> new
            end

          removed = removed -- [e]
          {new, removed}

        %{"organization" => e} ->
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
       new_project_organizations: new,
       removed_project_organizations: removed
     )}
  end

  def handle_event("update_notes", %{"notes" => notes}, socket) do
    {:noreply, assign(socket, notes: notes)}
  end

  def handle_event("submit_suggestions", _params, socket) do
    attrs = %{
      project_id: socket.assigns.selected_project.id,
      added_organizations: socket.assigns.new_project_organizations,
      removed_organizations: socket.assigns.removed_project_organizations,
      notes: socket.assigns.notes
    }

    case Sanbase.Ecosystem.ChangeSuggestion.create(attrs) do
      {:ok, _} ->
        socket =
          socket
          |> assign(
            selected_project: nil,
            added_organizations: [],
            removed_organizations: [],
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

  def add_gitub_organization(assigns) do
    ~H"""
    <div class="relative">
      <div class="absolute inset-y-0 start-0 flex items-center ps-3 pointer-events-none">
        <.icon name="hero-plus" class="text-gray-600" />
      </div>
      <input
        type="search"
        id="default-search"
        class="w-full p-4 ps-10 outline-none text-sm text-gray-900 border border-gray-300 rounded-lg bg-gray-50"
        placeholder="Suggest a new Github Organization"
        autocomplete="off"
        required
      />

      <button
        type="submit"
        class="text-white absolute end-2.5 bottom-2.5 bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium rounded-lg text-sm px-4 py-2 dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
      >
        Add Github Organization
      </button>
    </div>
    """
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
          phx-debounce="200"
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
              <span>Github Organizations</span>
            </li>
            <li :for={project <- @search_result} class="mx-2 last:pb-4">
              <.link
                phx-click={JS.add_class("hidden", to: "#search-result-suggestions")}
                patch={~p"/forms/suggest_github_organizations?selected_project=#{project.slug}"}
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
            <span class="text-lg leading-4">Current Github Organizations:</span>
            <UserFormsComponents.github_organizations_group
              github_organizations={
                @selected_project.github_organizations |> Enum.map(& &1.organization)
              }
              github_organization_colors_class="bg-blue-100 text-blue-800"
            />
          </div>
        </div>
      </div>
      <div :if={@new_project_organizations != []} class="px-8 py-4 border border-gray-100 rounded-sm">
        <span class="text-lg">Added Github Organizationss:</span>
        <UserFormsComponents.github_organizations_group
          github_organizations={@new_project_organizations}
          github_organization_colors_class="bg-green-100 text-green-800"
        />
      </div>
      <div
        :if={@removed_project_organizations != []}
        class="px-8 py-4 border border-gray-100 rounded-sm"
      >
        <span class="text-lg">Removed Organizations:</span>
        <UserFormsComponents.github_organizations_group
          github_organizations={@removed_project_organizations}
          github_organization_colors_class="bg-red-100 text-red-800"
        />
      </div>
    </div>
    """
  end

  def checkbox_select_organizations(assigns) do
    ~H"""
    <!-- Dropdown menu -->
    <div>
      <ul
        class="h-48 px-3 pb-3 overflow-y-auto text-sm text-gray-700"
        aria-labelledby="dropdownSearchButton"
      >
        <!-- li element that is shown if the search text is matching it -->
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3">
          <li :for={organization <- @stored_project_organizations}>
            <input
              id={"checkbox-item-#{organization.id}"}
              type="checkbox"
              checked={
                checked_organization?(
                  @stored_project_organizations,
                  @removed_project_organizations,
                  organization.organization
                )
              }
              name={organization.organization}
              phx-value-organization={organization.organization}
              phx-click="update_selected_organizations"
              class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded"
            />
            <label
              for={"checkbox-item-#{organization.id}"}
              class="w-full ms-2 text-sm font-medium text-gray-900 rounded"
            >
              <%= organization.organization %>
            </label>
          </li>
        </div>
      </ul>
    </div>
    """
  end

  def project_info(assigns) do
    organizations = Enum.map(assigns.project.github_organizations, & &1.organization)
    organizations_len = length(organizations)

    organizations_string =
      cond do
        organizations_len == 0 ->
          "none"

        organizations_len <= 3 ->
          Enum.join(organizations, ", ")

        true ->
          [e1, e2 | rest] = organizations
          "#{e1}, #{e2} and #{length(rest)} more"
      end

    assigns = assign(assigns, :organizations_string, organizations_string)

    ~H"""
    <div class="flex flex-row items-start justify-between">
      <div>
        <span><%= @project.name %></span>
        <span class="ml-4 text-gray-500"><%= @project.ticker %></span>
      </div>
      <span class="text-gray-500"><%= @organizations_string %></span>
    </div>
    """
  end

  attr(:text, :string, required: true)
  attr(:notes, :string, required: true)
  attr(:new_project_organizations, :list, required: true)
  attr(:removed_project_organizations, :list, required: true)
  attr(:rest, :global, doc: "the arbitrary HTML attributes to add to the flash container")

  def submit_suggestions_button(assigns) do
    is_disabled =
      assigns.new_project_organizations == [] and assigns.removed_project_organizations == [] and
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
            "You need to propose changes to the github organizations or leave a note in order to submit your proposal"
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

  defp checked_organization?(stored, removed, organization) do
    Enum.any?(stored, fn org -> org.organization == organization end) and
      organization not in removed
  end
end
