defmodule SanbaseWeb.HomeLive do
  @moduledoc false
  use SanbaseWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, stats_boxes: nil)}
  end

  def render(assigns) do
    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
      <%= case @stats_boxes do %>
        <% nil -> %>
          <div class="col-span-3 text-center py-8">
            <button
              phx-click="load_stats"
              class="bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded"
            >
              Load Statistics
            </button>
          </div>
        <% :loading -> %>
          <div class="col-span-3 text-center py-8">
            <p class="text-xl">Loading statistics...</p>
          </div>
        <% stats when is_list(stats) -> %>
          <%= for {title, stats} <- stats do %>
            <div class="bg-white shadow-md rounded-lg p-6">
              <h2 class="text-xl font-semibold mb-4">
                {String.capitalize(String.replace(title, "_", " "))}
              </h2>
              <ul>
                <%= for {key, value} <- stats do %>
                  <li class="flex justify-between items-center mb-2">
                    <span class="text-gray-600">
                      {String.replace(key, "_", " ") |> String.capitalize()}:
                    </span>
                    <span class="font-medium">
                      <%= if is_float(value) do %>
                        {:erlang.float_to_binary(value, decimals: 2)}
                      <% else %>
                        {value}
                      <% end %>
                    </span>
                  </li>
                <% end %>
              </ul>
            </div>
          <% end %>
      <% end %>
    </div>
    """
  end

  def handle_event("load_stats", _params, socket) do
    send(self(), :fetch_stats)
    {:noreply, assign(socket, stats_boxes: :loading)}
  end

  def handle_info(:fetch_stats, socket) do
    # Simulate a delay for loading
    Process.sleep(1000)

    stats = Sanbase.Statistics.get_all()
    {:noreply, assign(socket, stats_boxes: stats)}
  end
end
