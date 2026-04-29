defmodule SanbaseWeb.SuggestGithubOrganizationsLive do
  use SanbaseWeb, :live_view
  alias SanbaseWeb.UserFormsComponents
  alias SanbaseWeb.SuggestLiveHelpers

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
       stored_organizations: [],
       seen_organizations: [],
       new_organizations: [],
       removed_organizations: [],
       notes: "",
       search_result: projects,
       github_organization_input_error: "Organization name cannot be empty"
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
              stored_organizations = project.github_organizations |> Enum.map(& &1.organization)

              socket
              |> assign(
                selected_project: project,
                stored_organizations: stored_organizations,
                seen_organizations: stored_organizations,
                new_organizations: [],
                removed_organizations: []
              )
          end
      end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-300 mx-auto max-w-3xl p-6 shadow-sm min-h-96">
      <h1 class="text-2xl mb-6">Update the Github Organizations of an asset</h1>

      <.select_project search_result={@search_result} />

      <div :if={@selected_project}>
        <.selected_project_details
          selected_project={@selected_project}
          new_organizations={@new_organizations}
          removed_organizations={@removed_organizations}
        />

        <h2 class="text-lg mt-10">Edit the Github Organizations of the asset</h2>
        <p class="text-sm text-base-content/60 mt-1 mb-2">
          The selected organizations are going to be preserved or added, if they are not part of the current ones.
          The deselected organizations are going to be removed, if they are part of the current ones.
        </p>
        <.checkbox_select_organizations
          organizations={@stored_organizations}
          selected_project={@selected_project}
          stored_organizations={@stored_organizations}
          new_organizations={@new_organizations}
          removed_organizations={@removed_organizations}
          seen_organizations={@seen_organizations}
        />

        <.add_gitub_organization error={@github_organization_input_error} />

        <.notes_textarea />

        <.submit_suggestions_button
          text="Submit Suggestion"
          phx-submit="submit_suggestions"
          new_organizations={@new_organizations}
          removed_organizations={@removed_organizations}
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

  def handle_event("update_selected_organizations", params, socket) do
    stored = socket.assigns.stored_organizations
    new = socket.assigns.new_organizations
    removed = socket.assigns.removed_organizations
    seen = socket.assigns.seen_organizations

    {new, removed, seen} =
      case params do
        %{"value" => "on", "organization" => org} ->
          new =
            case org in stored do
              # Append to the back so it looks better in the UI
              false -> (new ++ [org]) |> Enum.uniq()
              true -> new
            end

          removed = removed -- [org]
          {new, removed, (seen ++ [org]) |> Enum.uniq()}

        %{"organization" => org} ->
          new = new -- [org]

          removed =
            case org in stored do
              true -> (removed ++ [org]) |> Enum.uniq()
              false -> removed
            end

          {new, removed, seen}
      end

    {:noreply,
     assign(socket,
       new_organizations: new,
       removed_organizations: removed,
       seen_organizations: seen
     )}
  end

  def handle_event("add_github_organization", %{"github_organization" => org}, socket) do
    %{
      new_organizations: new,
      removed_organizations: removed,
      stored_organizations: stored,
      seen_organizations: seen
    } = socket.assigns

    {new, removed} =
      cond do
        org in new or org in stored -> {new, removed}
        org in removed -> {new ++ [org], removed -- [org]}
        true -> {new ++ [org], removed}
      end

    socket =
      socket
      |> assign(
        new_organizations: new,
        removed_organizations: removed,
        seen_organizations: (seen ++ [org]) |> Enum.uniq()
      )

    {:noreply, socket}
  end

  def handle_event("update_notes", %{"notes" => notes}, socket) do
    {:noreply, assign(socket, notes: notes)}
  end

  def handle_event("submit_suggestions", _params, socket) do
    attrs = %{
      project_id: socket.assigns.selected_project.id,
      added_organizations: socket.assigns.new_organizations,
      removed_organizations: socket.assigns.removed_organizations,
      notes: socket.assigns.notes
    }

    case Sanbase.Project.GithubOrganization.ChangeSuggestion.create(attrs) do
      {:ok, _} ->
        socket =
          socket
          |> assign(
            selected_project: nil,
            added_organizations: [],
            removed_organizations: [],
            seen_organizations: [],
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

  def handle_event("validate_github_organization", %{"github_organization" => org}, socket) do
    error =
      cond do
        org in [nil, ""] ->
          "Organization name cannot be empty"

        String.starts_with?(org, ["http://", "https://", "www.", "github.com"]) ->
          "Do not add a URL, just the organization name"

        Regex.match?(~r{[^a-zA-Z0-9\-]}, org) ->
          "Organization name can only contain letters, numbers and hyphens"

        true ->
          nil
      end

    {:noreply, assign(socket, github_organization_input_error: error)}
  end

  def add_gitub_organization(assigns) do
    ~H"""
    <form phx-submit="add_github_organization" phx-change="validate_github_organization">
      <h2 class="text-lg mt-10">Suggest a new Github Organization</h2>
      <p class="text-sm text-base-content/60 mt-1 mb-2">
        Provide only the name of the Github Organization, not the full URL. <br />
        The Github URLs have the following structure: https://github.com/organization/repository
      </p>
      <div class="join w-full">
        <label class="input join-item flex-1">
          <.icon name="hero-plus" class="text-base-content/60" />
          <input
            type="search"
            name="github_organization"
            placeholder="Suggest a new Github Organization"
            autocomplete="off"
            phx-debounce="200"
            required
          />
        </label>
        <button
          type="submit"
          disabled={@error}
          title={@error}
          class="btn btn-primary join-item"
        >
          Add Github Organization
        </button>
      </div>
    </form>
    """
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
              <span>Github Organizations</span>
            </li>
            <li :for={project <- @search_result} class="mx-2 last:pb-4">
              <.link
                phx-click={JS.add_class("hidden", to: "#search-result-suggestions")}
                patch={~p"/forms/suggest_github_organizations?selected_project=#{project.slug}"}
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
            <span class="text-lg leading-4">Current Github Organizations:</span>
            <UserFormsComponents.github_organizations_group
              github_organizations={
                @selected_project.github_organizations |> Enum.map(& &1.organization)
              }
              github_organization_colors_class="badge-info"
            />
          </div>
        </div>
      </div>
      <div :if={@new_organizations != []} class="card bg-base-100 border border-base-300 px-8 py-4">
        <span class="text-lg">Added Github Organizations:</span>
        <UserFormsComponents.github_organizations_group
          github_organizations={@new_organizations}
          github_organization_colors_class="badge-success"
        />
      </div>
      <div
        :if={@removed_organizations != []}
        class="card bg-base-100 border border-base-300 px-8 py-4"
      >
        <span class="text-lg">Removed Organizations:</span>
        <UserFormsComponents.github_organizations_group
          github_organizations={@removed_organizations}
          github_organization_colors_class="badge-error"
        />
      </div>
    </div>
    """
  end

  def checkbox_select_organizations(assigns) do
    ~H"""
    <div>
      <ul
        class="h-48 px-3 pb-3 overflow-y-auto text-sm"
        aria-labelledby="dropdownSearchButton"
      >
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-2">
          <li :for={organization <- @seen_organizations}>
            <label class="label cursor-pointer justify-start gap-2">
              <input
                id={"checkbox-item-#{organization}"}
                type="checkbox"
                checked={
                  checked_organization?(
                    @stored_organizations,
                    @new_organizations,
                    @removed_organizations,
                    organization
                  )
                }
                name={organization}
                phx-value-organization={organization}
                phx-click="update_selected_organizations"
                class="checkbox checkbox-sm checkbox-primary"
              />
              <span class="text-sm font-medium">{organization}</span>
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
        <span>{@project.name}</span>
        <span class="ml-4 text-base-content/60">{@project.ticker}</span>
      </div>
      <span class="text-base-content/60">{@organizations_string}</span>
    </div>
    """
  end

  attr(:text, :string, required: true)
  attr(:notes, :string, required: true)
  attr(:new_organizations, :list, required: true)
  attr(:removed_organizations, :list, required: true)
  attr(:rest, :global, doc: "the arbitrary HTML attributes to add to the flash container")

  def submit_suggestions_button(assigns) do
    is_disabled =
      assigns.new_organizations == [] and assigns.removed_organizations == [] and
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
            "You need to propose changes to the github organizations or leave a note in order to submit your proposal"
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
        phx-debounce="500"
      ></textarea>
    </form>
    """
  end

  defp checked_organization?(stored, new, removed, organization) do
    (organization in stored or organization in new) and
      organization not in removed
  end
end
