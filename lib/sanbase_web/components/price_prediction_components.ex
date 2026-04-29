defmodule SanbaseWeb.PricePredictionComponents do
  use Phoenix.Component

  @doc """
  Renders a price prediction card
  """
  attr :prediction, :map, required: true
  attr :rest, :global

  def price_prediction_card(assigns) do
    ~H"""
    <div
      class="card bg-base-100 border border-base-300 p-3"
      id={"prediction-#{@prediction["id"]}"}
      {@rest}
    >
      <div class="flex justify-between text-xs text-base-content/60 mb-1">
        <span class="flex items-center gap-2">
          <span class="font-bold text-primary">
            {extract_account_name(@prediction["tweet_url"])}
          </span>
          <span
            :if={@prediction["prediction"]["asset"] != "N/A"}
            class="badge badge-sm badge-success badge-soft"
          >
            {@prediction["prediction"]["asset"]}
          </span>
        </span>
        <span>{format_date(@prediction["timestamp"])}</span>
      </div>

      <p class="mb-2 text-sm whitespace-pre-line">{@prediction["text"]}</p>

      <div class="flex items-center justify-between gap-2 mt-2">
        <div class="flex items-center gap-2">
          <span class="text-xs text-base-content/60">
            Confidence:
            <span class="font-semibold">
              {format_probability(@prediction["is_prediction_probability"])}
            </span>
          </span>

          <span
            :if={@prediction["prediction"]["prediction"]}
            class={["badge badge-sm", prediction_class(@prediction["prediction"]["prediction"])]}
          >
            {String.upcase(@prediction["prediction"]["prediction"])}
          </span>
        </div>

        <a
          href={@prediction["tweet_url"]}
          target="_blank"
          rel="noopener noreferrer"
          class="link link-primary text-xs"
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
        <a :if={!@maksim_filter} href="?maksim=true" class="btn btn-sm btn-soft">
          Show Maksim's
        </a>
        <a :if={@maksim_filter} href="?" class="btn btn-sm btn-soft">
          Show All
        </a>
        <button class="btn btn-sm btn-primary" phx-click="refresh" disabled={@loading}>
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
    <div class="border-b border-base-300 pb-3 mb-3">
      <div class="flex items-center gap-2 mb-2">
        <span class="text-sm font-medium">Filter by Asset:</span>
        <button :if={@selected_asset} class="btn btn-xs btn-soft" phx-click="clear_filter">
          Clear Filter ×
        </button>
      </div>

      <div class="flex flex-wrap gap-2">
        <button
          :for={{asset, count} <- @asset_counts}
          :if={count > 0}
          class={["btn btn-xs rounded-full", asset_filter_button_class(asset, @selected_asset)]}
          phx-click="filter_by_asset"
          phx-value-asset={asset}
        >
          <span class="font-medium">{format_asset_name(asset)}</span>
          <span class="opacity-75">({count})</span>
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

  defp prediction_class("up"), do: "badge-success"
  defp prediction_class("down"), do: "badge-error"
  defp prediction_class(_), do: "badge-ghost"

  defp asset_filter_button_class(asset, selected_asset) do
    if asset == selected_asset, do: "btn-primary", else: "btn-soft"
  end

  defp format_asset_name("N/A"), do: "No Asset"
  defp format_asset_name(asset), do: asset

  defp extract_account_name(tweet_url) do
    case URI.parse(tweet_url) do
      %URI{path: path} when is_binary(path) ->
        path
        |> String.split("/")
        |> Enum.at(1)
        |> case do
          nil -> "@Unknown"
          account -> "@#{account}"
        end

      _ ->
        "@Unknown"
    end
  end
end
