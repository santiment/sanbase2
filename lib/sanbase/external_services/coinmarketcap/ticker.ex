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
    :is_self_reported,
    :price_usd,
    :price_btc,
    :rank,
    :volume_usd,
    :market_cap_usd,
    :reported_market_cap_usd,
    :self_reported_market_cap_usd,
    :last_updated,
    :available_supply,
    :reported_available_supply,
    :self_reported_available_supply,
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
    |> handle_api_response("listings for top #{projects_number} projects")
  end

  @spec fetch_data_by_slug([String.t()]) :: {:error, String.t()} | {:ok, [%__MODULE__{}]}
  def fetch_data_by_slug(slugs) when is_list(slugs) do
    slug_str = Enum.join(slugs, ",")

    "v1/cryptocurrency/quotes/latest?slug=#{slug_str}&convert=USD,BTC"
    |> get()
    |> handle_api_response("quotes for #{length(slugs)} slugs")
  end

  defp handle_api_response(response, context) do
    case response do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        case parse_json(body) do
          {:ok, tickers} ->
            Logger.info("[CMC] Successfully fetched #{context} (#{length(tickers)} tickers).")
            {:ok, tickers}

          {:error, reason} ->
            error_msg = "[CMC] Failed to parse response for #{context}: #{reason}"
            Logger.error(error_msg)
            {:error, error_msg}
        end

      {:ok, %Tesla.Env{status: status, body: body}} when status in [401, 402, 403] ->
        error_msg =
          "[CMC] Auth/subscription error fetching #{context}. " <>
            "Status: #{status}. " <>
            "The API key may be invalid or the subscription may have been downgraded."

        Logger.error(error_msg)

        Sentry.capture_message("CMC API auth/subscription error",
          level: :error,
          extra: %{status: status, context: context, body: inspect(body, limit: 500)}
        )

        {:error, {:auth_error, status, error_msg}}

      {:ok, %Tesla.Env{status: 429, body: body}} ->
        error_msg = "[CMC] Rate limited fetching #{context}. Body: #{inspect(body, limit: 500)}"
        Logger.warning(error_msg)
        {:error, {:rate_limited, error_msg}}

      {:ok, %Tesla.Env{status: status, body: body}} when status >= 500 ->
        error_msg =
          "[CMC] Server error fetching #{context}. Status: #{status}. Body: #{inspect(body, limit: 500)}"

        Logger.error(error_msg)
        {:error, {:server_error, status, error_msg}}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        error_msg =
          "[CMC] Unexpected status #{status} fetching #{context}. Body: #{inspect(body, limit: 500)}"

        Logger.warning(error_msg)
        {:error, error_msg}

      {:error, error} ->
        error_msg = "[CMC] HTTP error fetching #{context}. Reason: #{inspect(error)}"
        Logger.error(error_msg)
        {:error, error_msg}
    end
  end

  defp parse_json(json) do
    %{"data" => data} = Jason.decode!(json)

    tickers =
      data
      |> Enum.map(fn project_data ->
        project_data =
          case project_data do
            {_, %{"id" => _id} = data} -> data
            %{"id" => _id} = data -> data
          end

        %{
          "id" => id,
          "name" => name,
          "symbol" => symbol,
          "slug" => slug,
          "cmc_rank" => rank,
          "circulating_supply" => reported_circulating_supply,
          "self_reported_circulating_supply" => self_reported_circulating_supply,
          "self_reported_market_cap" => self_reported_marketcap,
          "total_supply" => total_supply,
          "max_supply" => _max_supply,
          "last_updated" => last_updated,
          "quote" => %{
            "USD" => %{
              "price" => price_usd,
              "volume_24h" => volume_24h_usd,
              "market_cap" => reported_mcap_usd,
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

        # For now, override the values only for santiment. At the moment of writing
        # this code, more than 970 out of 3100 have 0 for marketcap and circulating supply.
        # Using self reported values for those projects would potentially introduce
        # less reliable data.
        {mcap_usd, circulating_supply, is_self_reported} =
          if slug == "santiment" and reported_mcap_usd == 0 do
            {self_reported_marketcap, self_reported_circulating_supply, true}
          else
            {reported_mcap_usd, reported_circulating_supply, false}
          end

        %__MODULE__{
          id: id,
          slug: slug,
          name: name,
          symbol: symbol,
          is_self_reported: is_self_reported,
          price_usd: price_usd,
          price_btc: price_btc,
          rank: rank,
          volume_usd: volume_24h_usd,
          market_cap_usd: mcap_usd,
          reported_market_cap_usd: reported_mcap_usd,
          self_reported_market_cap_usd: self_reported_marketcap,
          last_updated: last_updated,
          available_supply: circulating_supply,
          reported_available_supply: reported_circulating_supply,
          self_reported_available_supply: self_reported_circulating_supply,
          total_supply: total_supply,
          percent_change_1h: percent_change_1h_usd,
          percent_change_24h: percent_change_24h_usd,
          percent_change_7d: percent_change_7d_usd
        }
      end)
      |> Enum.filter(fn %__MODULE__{last_updated: last_updated} ->
        last_updated
      end)

    {:ok, tickers}
  rescue
    e ->
      {:error, "Failed to parse CMC JSON response: #{Exception.message(e)}"}
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
