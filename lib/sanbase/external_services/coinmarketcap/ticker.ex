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
    :volume_usd,
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
  alias Sanbase.ExternalServices.Coinmarketcap
  alias Sanbase.ExternalServices.Coinmarketcap.{PricePoint, TickerFetcher}

  require Logger
  alias Sanbase.Utils.Config

  plug(Sanbase.ExternalServices.RateLimiting.Middleware,
    name: :api_coinmarketcap_rate_limiter
  )

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
  def fetch_data(opts \\ []) do
    projects_number =
      case Keyword.get(opts, :projects_number) do
        count when is_integer(count) and count > 0 ->
          count

        _ ->
          Config.module_get(TickerFetcher, :projects_number)
          |> String.to_integer()
      end

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

        Logger.warning(error)
        {:error, error}

      {:error, error} ->
        error_msg =
          "Error fetching top #{projects_number} projects' information. Error message #{inspect(error)}"

        Logger.error(error_msg)

        {:error, error_msg}
    end
  end

  @spec parse_json(String.t()) :: [%__MODULE__{}] | no_return
  defp parse_json(json) do
    %{"data" => data} =
      json
      |> Jason.decode!()

    data =
      data
      |> Enum.map(fn project_data ->
        %{
          "id" => id,
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
          id: id,
          slug: slug,
          name: name,
          symbol: symbol,
          price_usd: price_usd,
          price_btc: price_btc,
          rank: rank,
          volume_usd: volume_24h_usd,
          market_cap_usd: mcap_usd,
          last_updated: last_updated,
          available_supply: circulating_supply,
          total_supply: total_supply,
          percent_change_1h: percent_change_1h_usd,
          percent_change_24h: percent_change_24h_usd,
          percent_change_7d: percent_change_7d_usd
        }
      end)
      |> Enum.filter(fn %__MODULE__{last_updated: last_updated} ->
        last_updated
      end)

    data
  end

  # Convert a Ticker to a PricePoint
  def to_price_point(%__MODULE__{} = ticker) do
    %__MODULE__{
      last_updated: last_updated,
      price_usd: price_usd,
      price_btc: price_btc,
      market_cap_usd: marketcap_usd,
      volume_usd: volume_usd
    } = ticker

    %PricePoint{
      datetime: DateTimeUtils.from_iso8601!(last_updated),
      price_usd: (price_usd || 0) |> to_float(),
      price_btc: (price_btc || 0) |> to_float(),
      marketcap_usd: (marketcap_usd || 0) |> to_integer(),
      volume_usd: (volume_usd || 0) |> to_integer()
    }
  end
end
