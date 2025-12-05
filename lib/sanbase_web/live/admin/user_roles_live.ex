defmodule SanbaseWeb.Admin.UserRolesLive do
  use SanbaseWeb, :live_view

  alias Sanbase.Accounts.{User, Role, UserRole}
  alias Sanbase.Repo
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    users = load_users_with_roles()
    roles = load_all_roles()

    socket =
      socket
      |> assign(:page_title, "User Roles")
      |> assign(:search_query, "")
      |> assign(:roles, roles)
      |> assign(:form, to_form(%{}, as: :role_assignment))
      |> assign(:email_query, "")
      |> assign(:email_suggestions, [])
      |> assign(:show_email_suggestions, false)
      |> assign(:selected_user_id, nil)
      |> stream(:users, users)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto p-6">
      <div class="max-w-7xl mx-auto">
        <h1 class="text-3xl font-bold text-gray-900 mb-6">User Roles Management</h1>

        <.assign_role_form
          form={@form}
          roles={@roles}
          email_query={@email_query}
          email_suggestions={@email_suggestions}
          show_email_suggestions={@show_email_suggestions}
          selected_user_id={@selected_user_id}
        />

        <div class="mt-8">
          <div class="mb-4">
            <input
              type="text"
              name="search_query"
              id="search-query-input"
              value={@search_query}
              phx-change="search_users"
              phx-debounce="300"
              placeholder="Search users by email, username, or name..."
              class="w-full max-w-md rounded-lg border border-zinc-300 px-3 py-2 text-zinc-900 focus:border-zinc-400 focus:ring-0 sm:text-sm sm:leading-6"
            />
          </div>

          <div class="bg-white shadow rounded-lg overflow-hidden">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    User
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Roles
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody id="users" phx-update="stream" class="bg-white divide-y divide-gray-200">
                <tr class="hidden only:block">
                  <td colspan="3" class="px-6 py-4 text-sm text-gray-500 text-center">
                    No users with roles found
                  </td>
                </tr>
                <tr :for={{id, user} <- @streams.users} id={id} class="hover:bg-gray-50">
                  <td class="px-6 py-4 whitespace-nowrap">
                    <div class="text-sm font-medium text-gray-900">
                      {user.name || user.username || user.email || "User ##{user.id}"}
                    </div>
                    <div class="text-sm text-gray-500">
                      {user.email}
                    </div>
                    <div :if={user.username} class="text-xs text-gray-400">
                      @{user.username}
                    </div>
                  </td>
                  <td class="px-6 py-4">
                    <div class="flex flex-wrap gap-2">
                      <span
                        :for={user_role <- user.roles}
                        class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800"
                      >
                        {user_role.role.name}
                      </span>
                    </div>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm font-medium">
                    <button
                      :for={user_role <- user.roles}
                      phx-click="remove_role"
                      phx-value-user_id={user.id}
                      phx-value-role_id={user_role.role_id}
                      class="text-red-600 hover:text-red-900 mr-2"
                      data-confirm="Are you sure you want to remove this role?"
                    >
                      Remove {user_role.role.name}
                    </button>
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

  attr :form, Phoenix.HTML.Form, required: true
  attr :roles, :list, required: true
  attr :email_query, :string, default: ""
  attr :email_suggestions, :list, default: []
  attr :show_email_suggestions, :boolean, default: false
  attr :selected_user_id, :string, default: nil

  def assign_role_form(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6 mb-6">
      <h2 class="text-xl font-semibold text-gray-900 mb-4">Assign Role to User</h2>
      <.form for={@form} phx-submit="assign_role" id="assign-role-form">
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div class="relative">
            <label for="user-email-input" class="block text-sm font-medium text-gray-700 mb-1">
              User Email (@santiment.net only)
            </label>
            <div phx-click-away="hide_email_suggestions">
              <input
                type="text"
                id="user-email-input"
                name="role_assignment[email]"
                value={@email_query}
                phx-keyup="search_email"
                phx-debounce="200"
                phx-click="show_email_suggestions"
                placeholder="Start typing email..."
                autocomplete="off"
                required
                class="w-full rounded-lg border border-zinc-300 px-3 py-2 text-zinc-900 focus:border-zinc-400 focus:ring-0 sm:text-sm sm:leading-6"
              />
              <input type="hidden" name="role_assignment[user_id]" value={@selected_user_id} />
              <div
                id="email-suggestions"
                class={[
                  "absolute z-10 mt-1 w-full bg-white border border-gray-300 rounded-md shadow-lg max-h-60 overflow-auto",
                  if(@show_email_suggestions && @email_suggestions != [], do: "", else: "hidden")
                ]}
              >
                <ul class="py-1">
                  <li
                    :for={suggestion <- @email_suggestions}
                    phx-click="select_email"
                    phx-value-user_id={suggestion.id}
                    phx-value-email={suggestion.email}
                    class="px-4 py-2 hover:bg-gray-100 cursor-pointer text-sm"
                  >
                    <div class="font-medium text-gray-900">{suggestion.email}</div>
                    <div :if={suggestion.name || suggestion.username} class="text-xs text-gray-500">
                      {suggestion.name || suggestion.username}
                    </div>
                  </li>
                  <li
                    :if={
                      @email_suggestions == [] && @email_query != "" && byte_size(@email_query) >= 2
                    }
                    class="px-4 py-2 text-sm text-gray-500"
                  >
                    No users found
                  </li>
                </ul>
              </div>
            </div>
          </div>
          <div>
            <.input
              type="select"
              field={@form[:role_id]}
              label="Role"
              options={[{"Select a role", ""} | Enum.map(@roles, fn r -> {r.name, r.id} end)]}
              required
            />
          </div>
          <div class="flex items-end">
            <.button type="submit" phx-disable-with="Assigning...">Assign Role</.button>
          </div>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def handle_event(
        "assign_role",
        %{"role_assignment" => %{"user_id" => user_id, "role_id" => role_id}},
        socket
      ) do
    cond do
      user_id == nil or user_id == "" ->
        {:noreply,
         put_flash(socket, :error, "Please select a user from the autocomplete suggestions")}

      true ->
        user_id = String.to_integer(user_id)
        role_id = String.to_integer(role_id)

        case Repo.get(User, user_id) do
          nil ->
            {:noreply, put_flash(socket, :error, "User not found")}

          user ->
            if not is_nil(user.email) and String.ends_with?(user.email, "@santiment.net") do
              case UserRole.create(user_id, role_id) do
                {:ok, _user_role} ->
                  users = load_users_with_roles(socket.assigns.search_query)

                  socket =
                    socket
                    |> put_flash(:info, "Role assigned successfully")
                    |> assign(:email_query, "")
                    |> assign(:email_suggestions, [])
                    |> assign(:selected_user_id, nil)
                    |> stream(:users, users, reset: true)

                  {:noreply, socket}

                {:error, changeset} ->
                  error_message =
                    case changeset.errors do
                      [] -> "Failed to assign role"
                      [{field, {message, _}} | _] -> "#{field}: #{message}"
                    end

                  {:noreply, put_flash(socket, :error, error_message)}
              end
            else
              {:noreply,
               put_flash(
                 socket,
                 :error,
                 "Only users with @santiment.net email addresses can be assigned roles"
               )}
            end
        end
    end
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
      |> assign(:show_email_suggestions, byte_size(query) >= 2 and suggestions != [])
      |> assign(:selected_user_id, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_email", %{"user_id" => user_id, "email" => email}, socket) do
    socket =
      socket
      |> assign(:email_query, email)
      |> assign(:selected_user_id, user_id)
      |> assign(:email_suggestions, [])
      |> assign(:show_email_suggestions, false)

    {:noreply, socket}
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
  def handle_event("remove_role", %{"user_id" => user_id, "role_id" => role_id}, socket) do
    user_id = String.to_integer(user_id)
    role_id = String.to_integer(role_id)

    case UserRole.delete(user_id, role_id) do
      {1, _} ->
        users = load_users_with_roles(socket.assigns.search_query)

        socket =
          socket
          |> put_flash(:info, "Role removed successfully")
          |> stream(:users, users, reset: true)

        {:noreply, socket}

      {0, _} ->
        {:noreply, put_flash(socket, :error, "Role not found")}
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

  defp load_all_roles do
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
