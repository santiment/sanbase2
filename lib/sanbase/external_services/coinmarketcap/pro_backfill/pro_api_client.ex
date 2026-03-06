defmodule Sanbase.ExternalServices.Coinmarketcap.ProBackfill.ProApiClient do
  alias Sanbase.ExternalServices.Coinmarketcap.PricePoint
  alias Sanbase.ExternalServices.RateLimiting.Server
  alias Sanbase.Utils.Config

  @rate_limiting_server :api_coinmarketcap_backfill_rate_limiter
  @path "/v2/cryptocurrency/quotes/historical"

  def fetch_range(cmc_integer_id, from_unix, to_unix, opts \\ []) do
    params = %{
      id: cmc_integer_id,
      interval: Keyword.get(opts, :interval, "5m"),
      convert: Keyword.get(opts, :convert, "USD,BTC"),
      time_start: DateTime.from_unix!(from_unix) |> DateTime.to_iso8601(),
      time_end: DateTime.from_unix!(to_unix) |> DateTime.to_iso8601()
    }

    Server.wait(@rate_limiting_server)

    case Req.get(base_url: base_url(), url: @path, headers: headers(), params: params) do
      {:ok, %{status: 200, body: body}} ->
        with {:ok, price_points} <- body_to_price_points(body) do
          {:ok, price_points, usage_from_body(body, 1, 0)}
        end

      {:ok, %{status: 429, headers: headers}} ->
        wait_seconds = header_value(headers, "retry-after") |> Sanbase.Math.to_integer() |> max(1)
        wait_until = Timex.shift(Timex.now(), seconds: wait_seconds)
        Server.wait_until(@rate_limiting_server, wait_until)
        {:rate_limited, wait_seconds, %{api_calls_total: 1, rate_limited_calls_total: 1}}

      {:ok, %{status: status, body: body}} ->
        {:error, "CoinMarketCap Pro API status #{status}. Body: #{inspect(body)}"}

      {:error, error} ->
        {:error, inspect(error)}
    end
  end

  defp body_to_price_points(%{"status" => %{"error_code" => 0}, "data" => data}) do
    quotes = Map.get(data, "quotes", [])

    price_points =
      quotes
      |> Enum.map(fn %{"timestamp" => timestamp, "quote" => quote} ->
        usd = Map.get(quote, "USD", %{})
        btc = Map.get(quote, "BTC", %{})

        %PricePoint{
          datetime: Sanbase.DateTimeUtils.from_iso8601!(timestamp),
          price_usd: Sanbase.Math.to_float(Map.get(usd, "price")),
          price_btc: Sanbase.Math.to_float(Map.get(btc, "price")),
          marketcap_usd: Sanbase.Math.to_integer(Map.get(usd, "market_cap")),
          volume_usd: Sanbase.Math.to_integer(Map.get(usd, "volume_24h"))
        }
      end)

    {:ok, price_points}
  end

  defp body_to_price_points(body) do
    {:error, "Unexpected CMC Pro response: #{inspect(body)}"}
  end

  defp usage_from_body(%{"status" => status}, api_calls, rate_limited_calls) do
    credits = Map.get(status, "credit_count", 0) |> Sanbase.Math.to_float()

    %{
      api_credits_used: credits,
      api_calls_total: api_calls,
      rate_limited_calls_total: rate_limited_calls,
      usage_precision: "exact"
    }
  end

  defp usage_from_body(_body, api_calls, rate_limited_calls) do
    %{
      api_credits_used: 0.0,
      api_calls_total: api_calls,
      rate_limited_calls_total: rate_limited_calls,
      usage_precision: "estimated"
    }
  end

  defp headers do
    [
      {"X-CMC_PRO_API_KEY", Config.module_get(Sanbase.ExternalServices.Coinmarketcap, :api_key)},
      {"Accept", "application/json"}
    ]
  end

  defp base_url do
    Config.module_get(Sanbase.ExternalServices.Coinmarketcap, :api_url)
  end

  defp header_value(headers, key) do
    headers
    |> Enum.find_value(fn {k, v} -> if String.downcase(k) == key, do: v, else: nil end)
  end
end
