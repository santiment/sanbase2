defmodule SanbaseWeb.Graphql.Resolvers.TechIndicatorsResolver do
  require Sanbase.Utils.Config
  alias Sanbase.Utils.Config

  @http_client Mockery.of("HTTPoison")
  @recv_timeout 15_000

  def macd(_root, %{ticker: ticker, currency: currency, from: from, to: to, interval: interval}, _resolution) do
    from_unix = DateTime.to_unix(from, :nanoseconds)
    to_unix = DateTime.to_unix(to, :nanoseconds)

    url = "#{tech_indicators_url()}/indicator/macd?ticker=#{ticker}&currency=#{currency}&from_timestamp=#{from_unix}&to_timestamp=#{to_unix}&aggregate_interval=#{interval}"

    options = [recv_timeout: @recv_timeout]

    case @http_client.get(url, [], options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Poison.decode(body)

        result =
          result
          |> Enum.map(fn
            %{"timestamp" => timestamp, "macd" => nil} ->
              %{datetime: DateTime.from_unix!(timestamp, :nanoseconds), macd: nil}
            %{"timestamp" => timestamp, "macd" => macd} ->
              %{datetime: DateTime.from_unix!(timestamp, :nanoseconds), macd: Decimal.new(macd)}
          end)

        {:ok, result}

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        {:error, "Error status #{status} fetching macd for ticker #{ticker}: #{body}"}

      res ->
        {:error, "Cannot fetch macd data for ticker #{ticker}"}
    end
  end

  def rsi(_root, %{ticker: ticker, currency: currency, from: from, to: to, interval: interval, rsi_interval: rsi_interval}, _resolution) do
    from_unix = DateTime.to_unix(from, :nanoseconds)
    to_unix = DateTime.to_unix(to, :nanoseconds)

    url = "#{tech_indicators_url()}/indicator/rsi?ticker=#{ticker}&currency=#{currency}&from_timestamp=#{from_unix}&to_timestamp=#{to_unix}&aggregate_interval=#{interval}&rsi_interval=#{rsi_interval}"

    options = [recv_timeout: @recv_timeout]

    case @http_client.get(url, [], options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Poison.decode(body)

        result =
          result
          |> Enum.map(fn
            %{"timestamp" => timestamp, "rsi" => nil} ->
              %{datetime: DateTime.from_unix!(timestamp, :nanoseconds), rsi: nil}
            %{"timestamp" => timestamp, "rsi" => rsi} ->
              %{datetime: DateTime.from_unix!(timestamp, :nanoseconds), rsi: Decimal.new(rsi)}
          end)

        {:ok, result}

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        {:error, "Error status #{status} fetching rsi for ticker #{ticker}: #{body}"}

      res ->
        {:error, "Cannot fetch rsi data for ticker #{ticker}"}
    end
  end

  def price_volume_diff(_root, %{ticker: ticker, currency: currency, from: from, to: to, interval: interval}, _resolution) do
    from_unix = DateTime.to_unix(from, :nanoseconds)
    to_unix = DateTime.to_unix(to, :nanoseconds)

    url = "#{tech_indicators_url()}/indicator/pricevolumediff?ticker=#{ticker}&currency=#{currency}&from_timestamp=#{from_unix}&to_timestamp=#{to_unix}&aggregate_interval=#{interval}"

    options = [recv_timeout: @recv_timeout]

    case @http_client.get(url, [], options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Poison.decode(body)

        result =
          result
          |> Enum.map(fn
            %{"timestamp" => timestamp, "price_volume_diff" => nil} ->
              %{datetime: DateTime.from_unix!(timestamp, :nanoseconds), price_volume_diff: nil}
            %{"timestamp" => timestamp, "price_volume_diff" => price_volume_diff} ->
              %{datetime: DateTime.from_unix!(timestamp, :nanoseconds), price_volume_diff: Decimal.new(price_volume_diff)}
          end)

        {:ok, result}

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        {:error, "Error status #{status} fetching price-volume diff for ticker #{ticker}: #{body}"}

      res ->
        {:error, "Cannot fetch price-volume diff data for ticker #{ticker}"}
    end
  end

  defp tech_indicators_url() do
    Config.module_get(Sanbase.TechIndicators, :url)
  end
end
