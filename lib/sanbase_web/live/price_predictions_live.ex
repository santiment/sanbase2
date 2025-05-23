defmodule SanbaseWeb.PricePredictionsLive do
  use SanbaseWeb, :live_view

  alias Sanbase.TweetsApi
  import SanbaseWeb.PricePredictionComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       predictions: [],
       filtered_predictions: [],
       loading: true,
       maksim_filter: false,
       selected_asset: nil,
       asset_counts: []
     )}
  end

  @impl true
  def handle_params(%{"maksim" => "true"}, _url, socket) do
    if connected?(socket) do
      send(self(), {:fetch_predictions, true})
    end

    {:noreply, assign(socket, maksim_filter: true, loading: true)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    if connected?(socket) do
      send(self(), {:fetch_predictions, false})
    end

    {:noreply, assign(socket, maksim_filter: false, loading: true)}
  end

  @impl true
  def handle_info({:fetch_predictions, maksim_filter}, socket) do
    case TweetsApi.fetch_price_predictions(maksim: maksim_filter) do
      {:ok, predictions} ->
        asset_counts = calculate_asset_counts(predictions)

        filtered_predictions =
          filter_predictions_by_asset(predictions, socket.assigns.selected_asset)

        {:noreply,
         assign(socket,
           predictions: predictions,
           filtered_predictions: filtered_predictions,
           asset_counts: asset_counts,
           loading: false
         )}

      {:error, _reason} ->
        {:noreply,
         assign(socket,
           predictions: [],
           filtered_predictions: [],
           asset_counts: [],
           loading: false
         )}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    send(self(), {:fetch_predictions, socket.assigns.maksim_filter})
    {:noreply, assign(socket, loading: true)}
  end

  @impl true
  def handle_event("filter_by_asset", %{"asset" => asset}, socket) do
    filtered_predictions = filter_predictions_by_asset(socket.assigns.predictions, asset)

    {:noreply,
     assign(socket,
       selected_asset: asset,
       filtered_predictions: filtered_predictions
     )}
  end

  @impl true
  def handle_event("clear_filter", _params, socket) do
    {:noreply,
     assign(socket,
       selected_asset: nil,
       filtered_predictions: socket.assigns.predictions
     )}
  end

  defp calculate_asset_counts(predictions) do
    predictions
    |> Enum.group_by(fn prediction ->
      get_in(prediction, ["prediction", "asset"]) || "N/A"
    end)
    |> Enum.map(fn {asset, predictions_for_asset} ->
      {asset, length(predictions_for_asset)}
    end)
    |> Enum.sort_by(fn {_asset, count} -> count end, :desc)
  end

  defp filter_predictions_by_asset(predictions, nil), do: predictions

  defp filter_predictions_by_asset(predictions, selected_asset) do
    Enum.filter(predictions, fn prediction ->
      asset = get_in(prediction, ["prediction", "asset"]) || "N/A"
      asset == selected_asset
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <div class="bg-white p-4 rounded-lg shadow">
        <.price_prediction_header
          title="Price Predictions"
          loading={@loading}
          maksim_filter={@maksim_filter}
        />

        <div :if={!@loading and not Enum.empty?(@asset_counts)} class="mb-4">
          <.asset_filter_section asset_counts={@asset_counts} selected_asset={@selected_asset} />
        </div>

        <div class="text-sm text-gray-700 mb-4 px-2">
          <span>Total Predictions: <span class="font-semibold">{length(@predictions)}</span></span>
          <span :if={@selected_asset} class="ml-4">
            Filtered: <span class="font-semibold">{length(@filtered_predictions)}</span>
          </span>
          <span :if={@maksim_filter} class="ml-2 px-2 py-1 bg-blue-100 text-blue-800 text-xs rounded">
            Maksim's Tweets
          </span>
        </div>

        <div :if={@loading} class="flex justify-center items-center h-16">
          <p class="text-sm text-gray-500">Loading predictions...</p>
        </div>

        <div
          :if={!@loading and Enum.empty?(@predictions)}
          class="flex flex-col items-center justify-center h-32 text-center"
        >
          <p class="text-sm text-gray-500 mb-2">No predictions available</p>
          <button
            class="bg-blue-500 hover:bg-blue-700 text-white text-xs font-bold py-1 px-2 rounded"
            phx-click="refresh"
          >
            Refresh
          </button>
        </div>

        <div :if={!@loading and not Enum.empty?(@filtered_predictions)} class="space-y-4">
          <.price_prediction_card :for={prediction <- @filtered_predictions} prediction={prediction} />
        </div>

        <div
          :if={!@loading and Enum.empty?(@filtered_predictions) and @selected_asset}
          class="flex flex-col items-center justify-center h-32 text-center"
        >
          <p class="text-sm text-gray-500 mb-2">No predictions for {@selected_asset}</p>
          <button
            class="bg-gray-500 hover:bg-gray-700 text-white text-xs font-bold py-1 px-2 rounded"
            phx-click="clear_filter"
          >
            Show All
          </button>
        </div>
      </div>
    </div>
    """
  end
end
