defmodule SanbaseWeb.UserStatsLive do
  use SanbaseWeb, :live_view

  alias Sanbase.Accounts.UserStats
  alias Sanbase.Cache

  @cache_key "user_stats_inactive_free_users"
  # 10 minutes
  @cache_ttl 600

  def mount(_params, _session, socket) do
    if connected?(socket) do
      send(self(), :load_stats)
    end

    socket =
      socket
      |> assign(:loading, true)
      |> assign(:stats, nil)
      |> assign(:error, nil)
      |> assign(:last_updated, nil)

    {:ok, socket}
  end

  def handle_info(:load_stats, socket) do
    case load_cached_stats() do
      {:ok, {stats, last_updated}} ->
        socket =
          socket
          |> assign(:loading, false)
          |> assign(:stats, stats)
          |> assign(:last_updated, last_updated)
          |> assign(:error, nil)

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:loading, false)
          |> assign(:error, reason)

        {:noreply, socket}
    end
  end

  def handle_event("refresh", _params, socket) do
    Cache.clear(@cache_key)
    send(self(), :load_stats)

    socket = assign(socket, :loading, true)
    {:noreply, socket}
  end

  defp load_cached_stats do
    Cache.get_or_store({@cache_key, @cache_ttl}, fn ->
      case UserStats.get_all_stats() do
        {:ok, stats} ->
          {:ok, {stats, DateTime.utc_now()}}

        {:error, reason} ->
          {:error, "Failed to load stats: #{reason}"}
      end
    end)
  end

  def render(assigns) do
    ~H"""
    <div class="container mx-auto p-6">
      <div class="max-w-4xl mx-auto">
        <.page_header loading={@loading} />

        <.error_message :if={@error} error={@error} />

        <.stats_content :if={@stats} stats={@stats} last_updated={@last_updated} />

        <.loading_state :if={@loading and is_nil(@stats)} />
      </div>
    </div>
    """
  end

  attr :loading, :boolean, required: true

  defp page_header(assigns) do
    ~H"""
    <div class="flex justify-between items-center mb-8">
      <h1 class="text-3xl font-bold text-gray-900">User Activity Statistics</h1>
      <button
        phx-click="refresh"
        class="bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded"
        disabled={@loading}
      >
        <.refresh_button_content loading={@loading} />
      </button>
    </div>
    """
  end

  attr :loading, :boolean, required: true

  defp refresh_button_content(assigns) do
    ~H"""
    <%= if @loading do %>
      <span class="inline-flex items-center">
        <.loading_spinner /> Loading...
      </span>
    <% else %>
      Refresh
    <% end %>
    """
  end

  defp loading_spinner(assigns) do
    ~H"""
    <svg
      class="animate-spin -ml-1 mr-3 h-5 w-5 text-white"
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

  attr :stats, :map, required: true
  attr :last_updated, :any, required: true

  defp stats_content(assigns) do
    ~H"""
    <div class="grid gap-6 mb-8">
      <div class="grid md:grid-cols-2 gap-6">
        <.stat_card
          title="Inactive Free Users"
          value={@stats.inactive_free_users_count}
          description="Stopped using free account for 1 month, but used it in last 60 days"
          color="red"
          icon="info"
        />

        <.stat_card
          title="Trial Ended Inactive"
          value={@stats.trial_ended_inactive_users_count}
          description="Trial ended (between 1 month and 2 weeks ago). Inactive for the last 2 weeks"
          color="orange"
          icon="clock"
        />

        <.stat_card
          title="Cancelled API Customers"
          value={@stats.cancelled_api_customers_count}
          description="API customers who cancelled their subscriptions in the last month. Don't have active API subscription."
          color="purple"
          icon="x"
        />

        <.stat_card
          title="Inactive Active API Customers"
          value={@stats.inactive_active_api_customers_count}
          description="Active subscription, but no API calls in the last 3 weeks"
          color="yellow"
          icon="warning"
        />
      </div>

      <.cache_info :if={@last_updated} last_updated={@last_updated} />
    </div>
    """
  end

  attr :title, :string, required: true
  attr :value, :integer, required: true
  attr :description, :string, required: true
  attr :color, :string, required: true
  attr :icon, :string, required: true

  defp stat_card(assigns) do
    ~H"""
    <div class={"bg-white rounded-lg shadow-lg p-6 border-l-4 border-#{@color}-500"}>
      <div class="flex items-center">
        <div class="flex-1">
          <h2 class="text-lg font-semibold text-gray-900 mb-2">
            {@title}
          </h2>
          <div class={"text-2xl font-bold text-#{@color}-600"}>
            {Number.Delimit.number_to_delimited(@value)}
          </div>
          <p class="text-gray-600 mt-1 text-sm">
            {@description}
          </p>
        </div>
        <div class={"text-#{@color}-500"}>
          <.stat_icon icon={@icon} />
        </div>
      </div>
    </div>
    """
  end

  attr :icon, :string, required: true

  defp stat_icon(%{icon: "info"} = assigns) do
    ~H"""
    <svg class="w-12 h-12" fill="currentColor" viewBox="0 0 20 20">
      <path
        fill-rule="evenodd"
        d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z"
        clip-rule="evenodd"
      >
      </path>
    </svg>
    """
  end

  defp stat_icon(%{icon: "clock"} = assigns) do
    ~H"""
    <svg class="w-12 h-12" fill="currentColor" viewBox="0 0 20 20">
      <path
        fill-rule="evenodd"
        d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z"
        clip-rule="evenodd"
      >
      </path>
    </svg>
    """
  end

  defp stat_icon(%{icon: "x"} = assigns) do
    ~H"""
    <svg class="w-12 h-12" fill="currentColor" viewBox="0 0 20 20">
      <path
        fill-rule="evenodd"
        d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z"
        clip-rule="evenodd"
      >
      </path>
    </svg>
    """
  end

  defp stat_icon(%{icon: "warning"} = assigns) do
    ~H"""
    <svg class="w-12 h-12" fill="currentColor" viewBox="0 0 20 20">
      <path
        fill-rule="evenodd"
        d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z"
        clip-rule="evenodd"
      >
      </path>
    </svg>
    """
  end

  attr :last_updated, :any, required: true

  defp cache_info(assigns) do
    ~H"""
    <div class="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
      <div class="flex items-center">
        <svg class="w-5 h-5 text-yellow-400 mr-2" fill="currentColor" viewBox="0 0 20 20">
          <path
            fill-rule="evenodd"
            d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z"
            clip-rule="evenodd"
          >
          </path>
        </svg>
        <p class="text-yellow-800">
          <strong>Last calculated:</strong>
          {Calendar.strftime(@last_updated, "%Y-%m-%d %H:%M:%S UTC")} (cached for 10 minutes)
        </p>
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
        <p class="text-gray-600">Loading user statistics...</p>
      </div>
    </div>
    """
  end
end
