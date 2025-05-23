defmodule SanbaseWeb.PricePredictionComponents do
  use Phoenix.Component

  @doc """
  Renders a price prediction card
  """
  attr :prediction, :map, required: true
  attr :rest, :global

  def price_prediction_card(assigns) do
    ~H"""
    <div class="border rounded-lg p-3" id={"prediction-#{@prediction["id"]}"} {@rest}>
      <div class="flex justify-between text-xs text-gray-500 mb-1">
        <span class="flex items-center gap-2">
          <span class="font-bold">Prediction ID: {@prediction["id"]}</span>
          <span
            :if={@prediction["prediction"]["asset"] != "N/A"}
            class="px-2 py-0.5 bg-green-100 text-green-800 rounded text-xs"
          >
            {@prediction["prediction"]["asset"]}
          </span>
        </span>
        <span>{format_date(@prediction["timestamp"])}</span>
      </div>

      <p class="mb-2 text-sm whitespace-pre-line">{@prediction["text"]}</p>

      <div class="flex items-center justify-between gap-2 mt-2">
        <div class="flex items-center gap-2">
          <span class="text-xs text-gray-600">
            Confidence:
            <span class="font-semibold">
              {format_probability(@prediction["is_prediction_probability"])}
            </span>
          </span>

          <span
            :if={@prediction["prediction"]["prediction"]}
            class={[
              "px-2 py-0.5 text-xs rounded font-medium",
              prediction_class(@prediction["prediction"]["prediction"])
            ]}
          >
            {String.upcase(@prediction["prediction"]["prediction"])}
          </span>
        </div>

        <a
          href={@prediction["tweet_url"]}
          target="_blank"
          rel="noopener noreferrer"
          class="text-xs text-blue-500 hover:underline"
        >
          View on X
        </a>
      </div>
    </div>
    """
  end

  @doc """
  Renders a header with title and refresh button for price predictions
  """
  attr :title, :string, default: "Price Predictions"
  attr :loading, :boolean, default: false
  attr :maksim_filter, :boolean, default: false

  def price_prediction_header(assigns) do
    ~H"""
    <div class="flex justify-between items-center mb-3">
      <h2 class="text-xl font-bold">{@title}</h2>
      <div class="flex items-center gap-2">
        <a
          :if={!@maksim_filter}
          href="?maksim=true"
          class="bg-gray-500 hover:bg-gray-700 text-white text-sm font-bold py-1 px-3 rounded"
        >
          Show Maksim's
        </a>
        <a
          :if={@maksim_filter}
          href="?"
          class="bg-gray-500 hover:bg-gray-700 text-white text-sm font-bold py-1 px-3 rounded"
        >
          Show All
        </a>
        <button
          class="bg-blue-500 hover:bg-blue-700 text-white text-sm font-bold py-1 px-3 rounded"
          phx-click="refresh"
          disabled={@loading}
        >
          Refresh
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders asset filter section with clickable asset tags showing prediction counts
  """
  attr :asset_counts, :list, required: true
  attr :selected_asset, :string, default: nil

  def asset_filter_section(assigns) do
    ~H"""
    <div class="border-b pb-3 mb-3">
      <div class="flex items-center gap-2 mb-2">
        <span class="text-sm font-medium text-gray-700">Filter by Asset:</span>
        <button
          :if={@selected_asset}
          class="text-xs px-2 py-1 bg-gray-200 text-gray-700 rounded hover:bg-gray-300"
          phx-click="clear_filter"
        >
          Clear Filter ×
        </button>
      </div>

      <div class="flex flex-wrap gap-2">
        <button
          :for={{asset, count} <- @asset_counts}
          :if={count > 0}
          class={[
            "text-xs px-3 py-1 rounded-full border transition-colors",
            asset_filter_button_class(asset, @selected_asset)
          ]}
          phx-click="filter_by_asset"
          phx-value-asset={asset}
        >
          <span class="font-medium">{format_asset_name(asset)}</span>
          <span class="ml-1 opacity-75">({count})</span>
        </button>
      </div>
    </div>
    """
  end

  # Helper functions
  defp format_date(datetime_str) do
    case DateTime.from_iso8601(datetime_str) do
      {:ok, datetime, _offset} ->
        datetime
        |> DateTime.to_naive()
        |> NaiveDateTime.to_string()
        |> String.replace("T", ", ")

      _ ->
        datetime_str
    end
  end

  defp format_probability(probability) when is_float(probability) do
    "#{Float.round(probability * 100, 2)}%"
  end

  defp format_probability(_), do: "N/A"

  defp prediction_class("up"), do: "bg-green-100 text-green-800"
  defp prediction_class("down"), do: "bg-red-100 text-red-800"
  defp prediction_class(_), do: "bg-gray-100 text-gray-800"

  defp asset_filter_button_class(asset, selected_asset) do
    if asset == selected_asset do
      "bg-blue-500 text-white border-blue-500"
    else
      "bg-white text-gray-700 border-gray-300 hover:bg-gray-50"
    end
  end

  defp format_asset_name("N/A"), do: "No Asset"
  defp format_asset_name(asset), do: asset
end
