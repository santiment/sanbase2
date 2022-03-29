defmodule SanbaseWeb.Graphql.Resolvers.PriceResolver do
  require Logger

  import SanbaseWeb.Graphql.Helpers.CalibrateInterval, only: [calibrate: 6]

  alias Sanbase.Price
  alias Sanbase.Model.Project

  @total_market "TOTAL_MARKET"
  @total_erc20 "TOTAL_ERC20"

  @doc """
  Returns a list of price points for the given ticker. Optimizes the number of queries
  to the DB by inspecting the requested fields.
  """
  def history_price(_root, %{slug: @total_market} = args, _resolution) do
    %{from: from, to: to, interval: interval} = args

    with {:ok, from, to, interval} <-
           calibrate(Price, @total_market, from, to, interval, 300),
         {:ok, result} <- Price.timeseries_data(@total_market, from, to, interval) do
      {:ok, result}
    end
  end

  def history_price(root, %{ticker: @total_market} = args, resolution) do
    args = args |> Map.delete(:ticker) |> Map.put(:slug, @total_market)
    history_price(root, args, resolution)
  end

  def history_price(_root, %{slug: @total_erc20} = args, _resolution) do
    %{from: from, to: to, interval: interval} = args

    case calibrate(Price, @total_erc20, from, to, interval, 300) do
      {:ok, from, to, interval} -> Price.timeseries_data(@total_erc20, from, to, interval)
      error -> error
    end
  end

  def history_price(root, %{ticker: @total_erc20} = args, resolution) do
    args = args |> Map.delete(:ticker) |> Map.put(:slug, @total_erc20)
    history_price(root, args, resolution)
  end

  def history_price(_root, %{ticker: ticker} = args, _resolution) do
    %{from: from, to: to, interval: interval} = args

    with {:get_slug, slug} when not is_nil(slug) <- {:get_slug, Project.slug_by_ticker(ticker)},
         {:ok, from, to, interval} <- calibrate(Price, slug, from, to, interval, 300),
         {:ok, result} <- Price.timeseries_data(slug, from, to, interval) do
      {:ok, result}
    else
      {:get_slug, nil} ->
        {:error,
         "The provided ticker '#{ticker}' is misspelled or there is no data for this ticker"}

      error ->
        {:error, "Cannot fetch history price for #{ticker}. Reason: #{inspect(error)}"}
    end
  end

  def history_price(_root, %{slug: slug} = args, _resolution) do
    %{from: from, to: to, interval: interval} = args

    with {:ok, from, to, interval} <- calibrate(Price, slug, from, to, interval, 300),
         {:ok, result} <- Price.timeseries_data(slug, from, to, interval) do
      {:ok, result}
    else
      {:get_ticker, nil} ->
        {:error, "The provided slug '#{slug}' is misspelled or there is no data for this slug"}

      error ->
        {:error, "Cannot fetch history price for #{slug}. Reason: #{inspect(error)}"}
    end
  end

  def ohlc(_root, %{slug: slug, from: from, to: to, interval: interval}, _resolution) do
    case Price.timeseries_ohlc_data(slug, from, to, interval) do
      {:ok, result} ->
        {:ok, result}

      {:error, error} ->
        {:error, "Cannot fetch ohlc for #{slug}. Reason: #{inspect(error)}"}
    end
  end

  def projects_list_stats(_root, %{slugs: slugs, from: from, to: to}, _resolution) do
    case Price.aggregated_marketcap_and_volume(slugs, from, to) do
      {:ok, values} ->
        {:ok, values}

      _ ->
        {:error, "Can't fetch combined volume and marketcap for slugs"}
    end
  end
end
