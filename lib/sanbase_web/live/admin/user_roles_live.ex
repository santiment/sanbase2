defmodule SanbaseWeb.Admin.UserRolesLive do
  use SanbaseWeb, :live_view

  alias Sanbase.Accounts.{User, Role, UserRole}
  alias Sanbase.Repo
  import Ecto.Query

  @owner_only_error "Only an Admin Panel Owner can assign or remove roles"

  # The route's on_mount hook covers mount and reconnect only, and a client can
  # push an event over the socket without ever rendering the form.
  defp owner?(socket) do
    Sanbase.Admin.Permissions.owner?(roles: socket.assigns[:current_user_role_names] || [])
  end

  @impl true
  def mount(_params, _session, socket) do
    users = load_users_with_roles()
    roles = load_all_roles()

    socket =
      socket
      |> assign(:page_title, "User Roles")
      |> assign(:search_query, "")
      |> assign(:roles, roles)
      |> assign(:roles_form, to_form(%{}, as: :roles))
      |> assign(:email_query, "")
      |> assign(:email_suggestions, [])
      |> assign(:show_email_suggestions, false)
      |> assign_selection(nil, MapSet.new())
      |> stream(:users, users)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"user_id" => user_id}, _uri, socket) do
    with {id, ""} <- Integer.parse(user_id),
         %User{} = user <- Repo.get(User, id) do
      {:noreply, select_user(socket, user)}
    else
      _ ->
        {:noreply,
         socket
         |> put_flash(:error, "User not found")
         |> assign_selection(nil, MapSet.new())}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign_selection(socket, nil, MapSet.new())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto p-6">
      <div class="max-w-7xl mx-auto">
        <h1 class="text-3xl font-bold mb-6">User Roles Management</h1>

        <.user_picker
          email_query={@email_query}
          email_suggestions={@email_suggestions}
          show_email_suggestions={@show_email_suggestions}
        />

        <.roles_editor
          :if={@selected_user}
          form={@roles_form}
          user={@selected_user}
          current_user_id={@current_user.id}
          roles={@roles}
          saved_role_ids={@saved_role_ids}
          checked_role_ids={@checked_role_ids}
        />

        <div class="mt-8">
          <h2 class="text-xl font-semibold mb-4">Users with roles</h2>
          <div class="mb-4">
            <input
              type="text"
              name="search_query"
              id="search-query-input"
              value={@search_query}
              phx-change="search_users"
              phx-debounce="300"
              placeholder="Search users by email, username, or name..."
              class="input input-sm w-full max-w-md"
            />
          </div>

          <div class="rounded-box border border-base-300 overflow-hidden">
            <table class="table table-zebra table-sm">
              <thead>
                <tr>
                  <th>User</th>
                  <th>Roles</th>
                  <th></th>
                </tr>
              </thead>
              <tbody id="users" phx-update="stream">
                <tr id="no-users-with-roles" class="hidden only:block">
                  <td colspan="3" class="text-center text-base-content/60 py-6">
                    No users with roles found
                  </td>
                </tr>
                <tr :for={{id, user} <- @streams.users} id={id}>
                  <td>
                    <div class="text-sm font-medium">{display_name(user)}</div>
                    <div class="text-sm text-base-content/60">{user.email}</div>
                    <div :if={user.username} class="text-xs text-base-content/50">
                      @{user.username}
                    </div>
                  </td>
                  <td>
                    <div class="flex flex-wrap gap-2">
                      <span :for={user_role <- user.roles} class="badge badge-sm badge-info">
                        {user_role.role.name}
                      </span>
                    </div>
                  </td>
                  <td class="text-right">
                    <.link
                      id={"edit-roles-#{user.id}"}
                      patch={~p"/admin/user_roles?user_id=#{user.id}"}
                      class="btn btn-xs btn-soft"
                    >
                      <.icon name="hero-pencil-square" class="size-3" /> Edit roles
                    </.link>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :email_query, :string, default: ""
  attr :email_suggestions, :list, default: []
  attr :show_email_suggestions, :boolean, default: false

  def user_picker(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-300 p-6 mb-6">
      <h2 class="text-xl font-semibold mb-4">Select User</h2>
      <fieldset class="fieldset relative max-w-md">
        <legend class="fieldset-legend">User Email (@santiment.net only)</legend>
        <div phx-click-away="hide_email_suggestions">
          <input
            type="text"
            id="user-email-input"
            name="email"
            value={@email_query}
            phx-keyup="search_email"
            phx-debounce="200"
            phx-click="show_email_suggestions"
            placeholder="Start typing email..."
            autocomplete="off"
            class="input input-sm w-full"
          />
          <ul
            id="email-suggestions"
            class={[
              "menu menu-sm bg-base-100 rounded-box shadow absolute z-10 mt-1 w-full max-h-60 overflow-auto",
              if(@show_email_suggestions && @email_suggestions != [], do: "", else: "hidden")
            ]}
          >
            <li
              :for={suggestion <- @email_suggestions}
              id={"email-suggestion-#{suggestion.id}"}
              phx-click="select_email"
              phx-value-user_id={suggestion.id}
            >
              <a>
                <div>
                  <div class="font-medium">{suggestion.email}</div>
                  <div
                    :if={suggestion.name || suggestion.username}
                    class="text-xs text-base-content/60"
                  >
                    {suggestion.name || suggestion.username}
                  </div>
                </div>
              </a>
            </li>
          </ul>
        </div>
      </fieldset>
    </div>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :user, User, required: true
  attr :current_user_id, :integer, required: true
  attr :roles, :list, required: true
  attr :saved_role_ids, MapSet, required: true
  attr :checked_role_ids, MapSet, required: true

  def roles_editor(assigns) do
    assigns =
      assigns
      |> assign(:to_grant, MapSet.difference(assigns.checked_role_ids, assigns.saved_role_ids))
      |> assign(:to_revoke, MapSet.difference(assigns.saved_role_ids, assigns.checked_role_ids))

    ~H"""
    <div id="roles-editor" class="card bg-base-100 border border-base-300 p-6 mb-6">
      <div class="flex items-start justify-between gap-4 mb-4">
        <div>
          <h2 class="text-xl font-semibold">{display_name(@user)}</h2>
          <div class="text-sm text-base-content/60">
            {@user.email || "(no email)"} · #{@user.id}
          </div>
          <div :if={not grantable?(@user)} class="text-xs text-warning mt-1">
            Only @santiment.net users can be granted roles — existing roles can still be revoked.
          </div>
        </div>
        <.link
          id="clear-selection"
          patch={~p"/admin/user_roles"}
          class="btn btn-sm btn-ghost btn-square"
          title="Close"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </.link>
      </div>

      <.form for={@form} id="user-roles-form" phx-change="change_roles" phx-submit="save_roles">
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-x-6 gap-y-1">
          <div
            :for={role <- @roles}
            class="flex items-center justify-between gap-2 rounded px-2 hover:bg-base-200 transition-colors"
            title={lock_reason(role, @user, @current_user_id, @saved_role_ids)}
          >
            <.input
              type="checkbox"
              id={"role-#{role.id}"}
              name={"roles[#{role.id}]"}
              label={role.name}
              checked={MapSet.member?(@checked_role_ids, role.id)}
              disabled={lock_reason(role, @user, @current_user_id, @saved_role_ids) != nil}
            />
            <span :if={MapSet.member?(@to_grant, role.id)} class="badge badge-xs badge-success">
              grant
            </span>
            <span :if={MapSet.member?(@to_revoke, role.id)} class="badge badge-xs badge-error">
              revoke
            </span>
          </div>
        </div>

        <div class="flex items-center justify-end gap-3 mt-6 pt-4 border-t border-base-300">
          <span :if={pending_changes?(@to_grant, @to_revoke)} class="text-sm text-base-content/60">
            {MapSet.size(@to_grant)} to grant, {MapSet.size(@to_revoke)} to revoke
          </span>
          <button
            type="button"
            id="reset-roles-button"
            phx-click="reset_roles"
            class="btn btn-sm btn-ghost"
            disabled={not pending_changes?(@to_grant, @to_revoke)}
          >
            Reset
          </button>
          <.button
            type="submit"
            id="save-roles-button"
            class="btn-sm btn-primary"
            phx-disable-with="Saving..."
            disabled={not pending_changes?(@to_grant, @to_revoke)}
          >
            Save
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def handle_event("search_email", %{"value" => query}, socket) do
    suggestions =
      if byte_size(query) >= 2 do
        search_santiment_users(query)
      else
        []
      end

    socket =
      socket
      |> assign(:email_query, query)
      |> assign(:email_suggestions, suggestions)
      |> assign(:show_email_suggestions, suggestions != [])

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_email", %{"user_id" => user_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/user_roles?user_id=#{user_id}")}
  end

  @impl true
  def handle_event("show_email_suggestions", _params, socket) do
    socket =
      if socket.assigns.email_suggestions != [] do
        assign(socket, :show_email_suggestions, true)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("hide_email_suggestions", _params, socket) do
    {:noreply, assign(socket, :show_email_suggestions, false)}
  end

  @impl true
  def handle_event("change_roles", %{"roles" => roles_params}, socket) do
    checked =
      desired_role_ids(roles_params, socket.assigns.saved_role_ids, socket.assigns.roles)

    {:noreply, assign(socket, :checked_role_ids, checked)}
  end

  def handle_event("change_roles", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("reset_roles", _params, socket) do
    {:noreply, assign(socket, :checked_role_ids, socket.assigns.saved_role_ids)}
  end

  @impl true
  def handle_event("save_roles", params, socket) do
    cond do
      not owner?(socket) ->
        {:noreply, put_flash(socket, :error, @owner_only_error)}

      is_nil(socket.assigns.selected_user) ->
        {:noreply, put_flash(socket, :error, "Please select a user first")}

      true ->
        save_roles(socket, Map.get(params, "roles", %{}))
    end
  end

  @impl true
  def handle_event("search_users", %{"search_query" => query}, socket) do
    users = load_users_with_roles(query)

    socket =
      socket
      |> assign(:search_query, query)
      |> stream(:users, users, reset: true)

    {:noreply, socket}
  end

  defp save_roles(socket, roles_params) do
    user = socket.assigns.selected_user
    # Diff against the DB, not the assigns — another Owner may have changed
    # this user's roles since the page loaded.
    current = user_role_ids(user.id)
    desired = desired_role_ids(roles_params, current, socket.assigns.roles)
    grant = MapSet.difference(desired, current) |> MapSet.to_list()
    revoke = MapSet.difference(current, desired) |> MapSet.to_list()

    cond do
      grant == [] and revoke == [] ->
        {:noreply, socket |> put_flash(:info, "No changes to save") |> select_user(user)}

      grant != [] and not grantable?(user) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Only users with @santiment.net email addresses can be assigned roles"
         )}

      user.id == socket.assigns.current_user.id and Role.admin_panel_owner_role_id() in revoke ->
        {:noreply, put_flash(socket, :error, "You cannot revoke your own Admin Panel Owner role")}

      true ->
        case UserRole.update_roles(user.id, grant, revoke) do
          {:ok, _changes} ->
            users = load_users_with_roles(socket.assigns.search_query)

            socket =
              socket
              |> put_flash(
                :info,
                "Roles saved: #{length(grant)} granted, #{length(revoke)} revoked"
              )
              |> select_user(user)
              |> stream(:users, users, reset: true)

            {:noreply, socket}

          {:error, _step, failed_value, _changes} ->
            {:noreply, put_flash(socket, :error, error_message(failed_value))}
        end
    end
  end

  defp select_user(socket, user) do
    socket
    |> assign_selection(user, user_role_ids(user.id))
    |> assign(:email_query, user.email || "")
    |> assign(:email_suggestions, [])
    |> assign(:show_email_suggestions, false)
  end

  defp assign_selection(socket, user, role_ids) do
    socket
    |> assign(:selected_user, user)
    |> assign(:saved_role_ids, role_ids)
    |> assign(:checked_role_ids, role_ids)
  end

  # A disabled checkbox submits nothing, so a role missing from the params
  # keeps its current state.
  defp desired_role_ids(roles_params, current_role_ids, roles) do
    Enum.reduce(roles, MapSet.new(), fn %Role{id: id}, acc ->
      case Map.get(roles_params, to_string(id)) do
        "true" -> MapSet.put(acc, id)
        "false" -> acc
        _ -> if MapSet.member?(current_role_ids, id), do: MapSet.put(acc, id), else: acc
      end
    end)
  end

  defp lock_reason(role, user, current_user_id, saved_role_ids) do
    cond do
      not grantable?(user) and not MapSet.member?(saved_role_ids, role.id) ->
        "Only @santiment.net users can be granted roles"

      user.id == current_user_id and role.id == Role.admin_panel_owner_role_id() and
          MapSet.member?(saved_role_ids, role.id) ->
        "You cannot revoke your own Admin Panel Owner role"

      true ->
        nil
    end
  end

  defp pending_changes?(to_grant, to_revoke) do
    MapSet.size(to_grant) > 0 or MapSet.size(to_revoke) > 0
  end

  defp grantable?(%User{email: email}) do
    is_binary(email) and String.ends_with?(email, "@santiment.net")
  end

  defp display_name(user) do
    user.name || user.username || user.email || "User ##{user.id}"
  end

  defp error_message(%Ecto.Changeset{errors: [{field, {message, _}} | _]}),
    do: "#{field}: #{message}"

  defp error_message(_), do: "Failed to save roles"

  defp user_role_ids(user_id) do
    from(ur in UserRole, where: ur.user_id == ^user_id, select: ur.role_id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp load_users_with_roles(search_query \\ "") do
    base_query =
      from(u in User,
        join: ur in assoc(u, :roles),
        distinct: true,
        preload: [roles: :role]
      )

    query =
      if search_query != "" do
        search_pattern = "%#{search_query}%"

        base_query
        |> where(
          [u],
          ilike(u.email, ^search_pattern) or
            ilike(u.username, ^search_pattern) or
            ilike(u.name, ^search_pattern)
        )
      else
        base_query
      end

    query
    |> order_by([u], desc: u.id)
    |> Repo.all()
  end

  defp load_all_roles() do
    from(r in Role, order_by: r.name)
    |> Repo.all()
  end

  defp search_santiment_users(query) do
    search_pattern = "%#{query}%"

    from(u in User,
      where:
        not is_nil(u.email) and ilike(u.email, "%@santiment.net") and
          ilike(u.email, ^search_pattern),
      select: %{
        id: u.id,
        email: u.email,
        name: u.name,
        username: u.username
      },
      limit: 10,
      order_by: [asc: u.email]
    )
    |> Repo.all()
  end
end
