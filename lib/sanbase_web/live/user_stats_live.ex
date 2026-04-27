defmodule SanbaseWeb.UserStatsLive do
  use SanbaseWeb, :live_view

  import SanbaseWeb.AdminLiveHelpers, only: [parse_int: 2]

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
    inactive_days = parse_int(params["inactive_days"], 14)
    prior_activity_days = parse_int(params["prior_activity_days"], 30)
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
      <h1 class="text-3xl font-bold">Inactive Users</h1>
      <p class="text-base-content/60 mt-2">Find and export users based on activity patterns</p>
    </div>
    """
  end

  attr :inactive_days, :integer, required: true
  attr :prior_activity_days, :integer, required: true
  attr :require_prior_activity, :boolean, required: true
  attr :loading, :boolean, required: true

  defp search_form(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-300 shadow p-6 mb-6">
      <.form for={%{}} id="search-form" phx-submit="search" class="space-y-4">
        <div class="grid md:grid-cols-3 gap-4">
          <fieldset class="fieldset">
            <legend class="fieldset-legend">Inactive for (days)</legend>
            <input
              type="number"
              id="inactive_days"
              name="inactive_days"
              value={@inactive_days}
              min="1"
              class="input w-full"
            />
          </fieldset>

          <fieldset class="fieldset">
            <legend class="fieldset-legend">Prior activity window (days)</legend>
            <input
              type="number"
              id="prior_activity_days"
              name="prior_activity_days"
              value={@prior_activity_days}
              min="1"
              class="input w-full"
            />
          </fieldset>

          <div class="flex items-end">
            <label class="label cursor-pointer gap-2">
              <input
                type="checkbox"
                id="require_prior_activity"
                name="require_prior_activity"
                value="true"
                checked={@require_prior_activity}
                class="checkbox checkbox-sm checkbox-primary"
              />
              <span class="text-sm">Require prior activity</span>
            </label>
          </div>
        </div>

        <div>
          <button type="submit" disabled={@loading} class="btn btn-primary">
            <%= if @loading do %>
              <span class="loading loading-spinner loading-xs"></span> Searching...
            <% else %>
              Search Inactive Users
            <% end %>
          </button>
        </div>
      </.form>
    </div>
    """
  end

  attr :error, :string, required: true

  defp error_message(assigns) do
    ~H"""
    <div class="alert alert-error mb-4" role="alert">
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
    <div class="card bg-base-100 border border-base-300 shadow p-6">
      <div class="flex justify-between items-center mb-6">
        <div>
          <h2 class="text-2xl font-bold">{@total_count}</h2>
          <p class="text-base-content/60">inactive users found</p>
        </div>

        <.link
          :if={@inactive_users != []}
          href={"/admin/download_inactive_users_csv?inactive_days=#{@inactive_days}&prior_activity_days=#{@prior_activity_days}&require_prior_activity=#{@require_prior_activity}"}
          download={@filename}
          class="btn btn-success"
        >
          Download CSV
        </.link>
      </div>

      <div class="mb-4">
        <h3 class="text-lg font-semibold mb-3">Preview (first 10)</h3>

        <div :if={@inactive_users == []} class="text-center py-8 text-base-content/50">
          No inactive users found matching the criteria.
        </div>

        <div :if={@inactive_users != []} class="rounded-box border border-base-300 overflow-x-auto">
          <table class="table table-zebra table-sm">
            <thead>
              <tr>
                <th>Email</th>
                <th>Name</th>
              </tr>
            </thead>
            <tbody>
              <%= for user <- Enum.take(@inactive_users, 10) do %>
                <tr>
                  <td>{user.email}</td>
                  <td class="text-base-content/60">{user.name || "friend"}</td>
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
        <span class="loading loading-spinner loading-lg text-primary mb-4"></span>
        <p class="text-base-content/60">Loading inactive users...</p>
      </div>
    </div>
    """
  end
end
