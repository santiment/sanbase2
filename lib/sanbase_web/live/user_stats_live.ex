defmodule SanbaseWeb.UserStatsLive do
  use SanbaseWeb, :live_view

  alias Sanbase.Accounts.UserStats

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:inactive_days, 14)
      |> assign(:prior_activity_days, 30)
      |> assign(:require_prior_activity, true)
      |> assign(:inactive_users, [])
      |> assign(:total_count, 0)
      |> assign(:loading, false)
      |> assign(:error, nil)

    {:ok, socket}
  end

  def handle_event("search", params, socket) do
    inactive_days = parse_integer(params["inactive_days"], 14)
    prior_activity_days = parse_integer(params["prior_activity_days"], 30)
    require_prior_activity = params["require_prior_activity"] == "true"

    socket =
      socket
      |> assign(:inactive_days, inactive_days)
      |> assign(:prior_activity_days, prior_activity_days)
      |> assign(:require_prior_activity, require_prior_activity)
      |> assign(:loading, true)
      |> assign(:error, nil)

    send(self(), :fetch_inactive_users)

    {:noreply, socket}
  end

  def handle_info(:fetch_inactive_users, socket) do
    %{
      inactive_days: inactive_days,
      prior_activity_days: prior_activity_days,
      require_prior_activity: require_prior_activity
    } = socket.assigns

    case UserStats.inactive_users_with_activity(
           inactive_days,
           prior_activity_days,
           require_prior_activity
         ) do
      {:ok, users} ->
        socket =
          socket
          |> assign(:inactive_users, users)
          |> assign(:total_count, length(users))
          |> assign(:loading, false)
          |> assign(:error, nil)

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:inactive_users, [])
          |> assign(:total_count, 0)
          |> assign(:loading, false)
          |> assign(:error, reason)

        {:noreply, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="container mx-auto p-6">
      <div class="max-w-6xl mx-auto">
        <.page_header />

        <.search_form
          inactive_days={@inactive_days}
          prior_activity_days={@prior_activity_days}
          require_prior_activity={@require_prior_activity}
          loading={@loading}
        />

        <.error_message :if={@error} error={@error} />

        <.results_section
          :if={not @loading}
          inactive_users={@inactive_users}
          total_count={@total_count}
          inactive_days={@inactive_days}
          prior_activity_days={@prior_activity_days}
          require_prior_activity={@require_prior_activity}
          filename={"inactive_users_#{DateTime.utc_now() |> DateTime.to_date()}.csv"}
        />

        <.loading_state :if={@loading} />
      </div>
    </div>
    """
  end

  defp page_header(assigns) do
    ~H"""
    <div class="mb-8">
      <h1 class="text-3xl font-bold text-gray-900">Inactive Users</h1>
      <p class="text-gray-600 mt-2">Find and export users based on activity patterns</p>
    </div>
    """
  end

  attr :inactive_days, :integer, required: true
  attr :prior_activity_days, :integer, required: true
  attr :require_prior_activity, :boolean, required: true
  attr :loading, :boolean, required: true

  defp search_form(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow-lg p-6 mb-6">
      <.form for={%{}} id="search-form" phx-submit="search" class="space-y-4">
        <div class="grid md:grid-cols-3 gap-4">
          <div>
            <label for="inactive_days" class="block text-sm font-medium text-gray-700 mb-1">
              Inactive for (days)
            </label>
            <input
              type="number"
              id="inactive_days"
              name="inactive_days"
              value={@inactive_days}
              min="1"
              class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>

          <div>
            <label for="prior_activity_days" class="block text-sm font-medium text-gray-700 mb-1">
              Prior activity window (days)
            </label>
            <input
              type="number"
              id="prior_activity_days"
              name="prior_activity_days"
              value={@prior_activity_days}
              min="1"
              class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>

          <div class="flex items-end">
            <label class="flex items-center cursor-pointer">
              <input
                type="checkbox"
                id="require_prior_activity"
                name="require_prior_activity"
                value="true"
                checked={@require_prior_activity}
                class="w-4 h-4 text-blue-500 rounded"
              />
              <span class="ml-2 text-sm text-gray-700">Require prior activity</span>
            </label>
          </div>
        </div>

        <div>
          <button
            type="submit"
            disabled={@loading}
            class="bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-6 rounded disabled:opacity-50 disabled:cursor-not-allowed"
          >
            <%= if @loading do %>
              <span class="inline-flex items-center">
                <.loading_spinner /> Searching...
              </span>
            <% else %>
              Search Inactive Users
            <% end %>
          </button>
        </div>
      </.form>
    </div>
    """
  end

  defp loading_spinner(assigns) do
    ~H"""
    <svg
      class="animate-spin -ml-1 mr-2 h-4 w-4 text-white"
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
    >
      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4">
      </circle>
      <path
        class="opacity-75"
        fill="currentColor"
        d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
      >
      </path>
    </svg>
    """
  end

  attr :error, :string, required: true

  defp error_message(assigns) do
    ~H"""
    <div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">
      <strong>Error:</strong> {@error}
    </div>
    """
  end

  attr :inactive_users, :list, required: true
  attr :total_count, :integer, required: true
  attr :inactive_days, :integer, required: true
  attr :prior_activity_days, :integer, required: true
  attr :require_prior_activity, :boolean, required: true
  attr :filename, :string, required: false

  defp results_section(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow-lg p-6">
      <div class="flex justify-between items-center mb-6">
        <div>
          <h2 class="text-2xl font-bold text-gray-900">
            {@total_count}
          </h2>
          <p class="text-gray-600">inactive users found</p>
        </div>

        <.link
          :if={@inactive_users != []}
          href={"/admin/download_inactive_users_csv?inactive_days=#{@inactive_days}&prior_activity_days=#{@prior_activity_days}&require_prior_activity=#{@require_prior_activity}"}
          download={@filename}
          class="bg-green-500 hover:bg-green-700 text-white font-bold py-2 px-4 rounded"
        >
          Download CSV
        </.link>
      </div>

      <div class="mb-4">
        <h3 class="text-lg font-semibold text-gray-900 mb-3">Preview (first 10)</h3>

        <div :if={@inactive_users == []} class="text-center py-8 text-gray-500">
          No inactive users found matching the criteria.
        </div>

        <div :if={@inactive_users != []} class="overflow-x-auto">
          <table class="w-full">
            <thead>
              <tr class="bg-gray-100 border-b border-gray-200">
                <th class="px-4 py-2 text-left text-sm font-semibold text-gray-700">Email</th>
                <th class="px-4 py-2 text-left text-sm font-semibold text-gray-700">Name</th>
              </tr>
            </thead>
            <tbody>
              <%= for user <- Enum.take(@inactive_users, 10) do %>
                <tr class="border-b border-gray-200 hover:bg-gray-50">
                  <td class="px-4 py-2 text-sm text-gray-900">
                    {user.email}
                  </td>
                  <td class="px-4 py-2 text-sm text-gray-600">
                    {user.name}
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  defp loading_state(assigns) do
    ~H"""
    <div class="flex justify-center items-center py-12">
      <div class="text-center">
        <svg
          class="animate-spin h-12 w-12 text-blue-500 mx-auto mb-4"
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
        >
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4">
          </circle>
          <path
            class="opacity-75"
            fill="currentColor"
            d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
          >
          </path>
        </svg>
        <p class="text-gray-600">Loading inactive users...</p>
      </div>
    </div>
    """
  end

  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} -> num
      :error -> default
    end
  end

  defp parse_integer(nil, default), do: default
end
