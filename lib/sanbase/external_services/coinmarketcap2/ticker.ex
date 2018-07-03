defmodule Sanbase.ExternalServices.Coinmarketcap.Ticker2 do
  @projects_number 10_000
  @moduledoc ~s"""
    Fetches the ticker data from coinmarketcap API `https://api.coinmarketcap.com/v1/ticker`

    A single request fetchest all top #{@projects_number} tickers information. The coinmarketcap API
    has somewhat misleading name for this api - `ticker` is _NOT_ unique - there
    duplicated tickers. The `id` field (called coinmarketcap_id everywhere in sanbase)
    is unique. Sanbase uses names in the format `TICKER_coinmarketcap_id` to construct
    informative and unique names.
  """

  defstruct [
    :id,
    :name,
    :symbol,
    :price_usd,
    :price_btc,
    :rank,
    :"24h_volume_usd",
    :market_cap_usd,
    :last_updated,
    :available_supply,
    :total_supply,
    :percent_change_1h,
    :percent_change_24h,
    :percent_change_7d
  ]

  use Tesla

  require Logger

  alias Sanbase.ExternalServices.RateLimiting
  # TODO: Change after switching over to only this cmc
  alias Sanbase.ExternalServices.Coinmarketcap.PricePoint2, as: PricePoint
  alias Sanbase.Influxdb.Measurement

  plug(RateLimiting.Middleware, name: :api_coinmarketcap_rate_limiter)
  plug(Tesla.Middleware.BaseUrl, "https://api.coinmarketcap.com/v1/ticker")
  plug(Tesla.Middleware.Compression)
  plug(Tesla.Middleware.Logger)

  alias __MODULE__, as: Ticker

  def fetch_data() do
    "/?limit=#{@projects_number}"
    |> get()
    |> case do
      %Tesla.Env{status: 200, body: body} ->
        {:ok, parse_json(body)}

      %Tesla.Env{status: status, body: _body} ->
        error =
          "Failed fetching top #{@projects_number} projects' information from /v1/ticker. Status: #{
            status
          }"

        Logger.warn(error)
        {:error, error}

      %Tesla.Error{message: error_msg} ->
        Logger.error(
          "Error fetching top #{@projects_number} projects' information from /v1/ticker. Error message #{
            inspect(error_msg)
          }"
        )

        {:error, error_msg}
    end
  end

  def parse_json(json) do
    json
    |> Poison.decode!(as: [%Ticker{}])
    |> Stream.filter(fn %Ticker{last_updated: last_updated} -> last_updated end)
    |> Enum.map(&make_timestamp_integer/1)
  end

  def convert_for_importing(
        %Ticker{
          last_updated: last_updated,
          price_btc: price_btc,
          price_usd: price_usd,
          "24h_volume_usd": volume_usd,
          market_cap_usd: marketcap_usd
        } = ticker
      ) do
    price_point = %PricePoint{
      marketcap_usd: marketcap_usd |> to_integer(),
      volume_usd: volume_usd |> to_integer(),
      price_btc: price_btc |> to_float(),
      price_usd: price_usd |> to_float(),
      datetime: DateTime.from_unix!(last_updated)
    }

    PricePoint.convert_to_measurement(price_point, Measurement.name_from(ticker))
  end

  # Helper functions

  defp make_timestamp_integer(%Ticker{last_updated: last_updated} = ticker) do
    {ts, ""} = Integer.parse(last_updated)
    %{ticker | last_updated: ts}
  end

  defp to_float(nil), do: nil
  defp to_float(fl) when is_float(fl), do: fl

  defp to_float(str) when is_binary(str) do
    {num, _} = str |> Float.parse()
    num
  end

  defp to_integer(nil), do: nil
  defp to_integer(int) when is_integer(int), do: int

  defp to_integer(str) when is_binary(str) do
    {num, _} = str |> Integer.parse()
    num
  end
end
