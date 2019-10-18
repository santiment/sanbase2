defmodule Sanbase.ExternalServices.Coinmarketcap.Ticker do
  @projects_number 5_000
  @moduledoc ~s"""
  Fetches the ticker data from coinmarketcap API `https://api.coinmarketcap.com/v2/ticker`

  A single request fetchest all top #{@projects_number} tickers information. The coinmarketcap API
  has somewhat misleading name for this api - `ticker` is _NOT_ unique - there
  duplicated tickers. The `id` field (called coinmarketcap_id everywhere in sanbase)
  is unique. Sanbase uses names in the format `TICKER_coinmarketcap_id` to construct
  informative and unique names.
  """

  defstruct [
    :id,
    :name,
    :slug,
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

  import Sanbase.Math, only: [to_integer: 1, to_float: 1]

  alias Sanbase.DateTimeUtils
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.ExternalServices.Coinmarketcap
  alias Sanbase.ExternalServices.Coinmarketcap.{PricePoint, TickerFetcher}

  require Logger
  require Sanbase.Utils.Config, as: Config

  plug(Sanbase.ExternalServices.RateLimiting.Middleware, name: :api_coinmarketcap_rate_limiter)

  plug(Tesla.Middleware.Headers, [
    {"X-CMC_PRO_API_KEY", Config.module_get(Coinmarketcap, :api_key)}
  ])

  plug(
    Tesla.Middleware.BaseUrl,
    Config.module_get(Coinmarketcap, :api_url)
  )

  plug(Tesla.Middleware.Compression)
  plug(Tesla.Middleware.Logger)

  @doc ~s"""
  Fetch the current data for all top N projects.
  Parse the binary received from the CMC response to a list of tickers
  """
  @spec fetch_data() :: {:error, String.t()} | {:ok, [%__MODULE__{}]}
  def fetch_data() do
    projects_number = Config.module_get(TickerFetcher, :projects_number) |> String.to_integer()

    Logger.info("[CMC] Fetching the realtime data for top #{projects_number} projects")

    "v1/cryptocurrency/listings/latest?start=1&sort=market_cap&limit=#{projects_number}&cryptocurrency_type=all&convert=USD,BTC"
    |> get()
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Logger.info(
          "[CMC] Successfully fetched the realtime data for top #{projects_number} projects."
        )

        {:ok, parse_json(body)}

      {:ok, %Tesla.Env{status: status}} ->
        error = "Failed fetching top #{projects_number} projects' information. Status: #{status}"

        Logger.warn(error)
        {:error, error}

      {:error, error} ->
        error_msg =
          "Error fetching top #{projects_number} projects' information. Error message #{
            inspect(error)
          }"

        Logger.error(error_msg)

        {:error, error_msg}
    end
  end

  @spec parse_json(String.t()) :: [%__MODULE__{}] | no_return
  defp parse_json(json) do
    %{"data" => data} =
      json
      |> Jason.decode!()

    data
    |> Enum.map(fn project_data ->
      %{
        "name" => name,
        "symbol" => symbol,
        "slug" => slug,
        "cmc_rank" => rank,
        "circulating_supply" => circulating_supply,
        "total_supply" => total_supply,
        "max_supply" => _max_supply,
        "last_updated" => last_updated,
        "quote" => %{
          "USD" => %{
            "price" => price_usd,
            "volume_24h" => volume_24h_usd,
            "market_cap" => mcap_usd,
            "percent_change_1h" => percent_change_1h_usd,
            "percent_change_24h" => percent_change_24h_usd,
            "percent_change_7d" => percent_change_7d_usd
          },
          "BTC" => %{
            "price" => price_btc,
            "volume_24h" => _volume_btc,
            "market_cap" => _mcap_btc,
            "percent_change_1h" => _percent_change_1h_btc,
            "percent_change_24h" => _percent_change_24h_btc,
            "percent_change_7d" => _percent_change_7d_btc
          }
        }
      } = project_data

      %__MODULE__{
        id: slug,
        name: name,
        symbol: symbol,
        price_usd: price_usd,
        price_btc: price_btc,
        rank: rank,
        "24h_volume_usd": volume_24h_usd,
        market_cap_usd: mcap_usd,
        last_updated: last_updated,
        available_supply: circulating_supply,
        total_supply: total_supply,
        percent_change_1h: percent_change_1h_usd,
        percent_change_24h: percent_change_24h_usd,
        percent_change_7d: percent_change_7d_usd
      }
    end)
    |> Enum.filter(fn %__MODULE__{last_updated: last_updated} -> last_updated end)
  end

  @spec convert_for_importing(%__MODULE__{}, %{}) :: [%Measurement{}]
  def convert_for_importing(
        %__MODULE__{
          last_updated: last_updated,
          price_btc: price_btc,
          price_usd: price_usd,
          "24h_volume_usd": volume_usd,
          market_cap_usd: marketcap_usd
        } = ticker,
        cmc_id_to_slugs_mapping
      ) do
    case Map.get(cmc_id_to_slugs_mapping, ticker.id, []) |> List.wrap() do
      [] ->
        []

      slugs ->
        Enum.map(slugs, fn slug ->
          price_point = %PricePoint{
            marketcap_usd: (marketcap_usd || 0) |> to_integer(),
            volume_usd: (volume_usd || 0) |> to_integer(),
            price_btc: (price_btc || 0) |> to_float(),
            price_usd: (price_usd || 0) |> to_float(),
            datetime: DateTimeUtils.from_iso8601!(last_updated)
          }

          PricePoint.convert_to_measurement(
            price_point,
            Measurement.name_from(%{ticker | id: slug})
          )
        end)
    end
  end
end
