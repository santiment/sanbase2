defmodule Sanbase.InternalServices.TechIndicators do
  require Logger
  require Sanbase.Utils.Config
  alias Sanbase.Utils.Config

  @http_client Mockery.of("HTTPoison")
  @recv_timeout 15_000

  def macd(
        ticker,
        currency,
        from_datetime,
        to_datetime,
        aggregate_interval,
        result_size_tail \\ 0
      ) do
    from_unix = DateTime.to_unix(from_datetime)
    to_unix = DateTime.to_unix(to_datetime)

    url = "#{tech_indicators_url()}/indicator/macd"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"ticker", ticker},
        {"currency", currency},
        {"from_timestamp", from_unix},
        {"to_timestamp", to_unix},
        {"aggregate_interval", aggregate_interval},
        {"result_size_tail", result_size_tail}
      ]
    ]

    case @http_client.get(url, [], options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Poison.decode(body)

        result =
          result
          |> Enum.map(fn %{"timestamp" => timestamp, "macd" => macd} ->
            %{datetime: DateTime.from_unix!(timestamp), macd: decimal_or_nil(macd)}
          end)

        {:ok, result}

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        message = "Error status #{status} fetching macd for ticker #{ticker}: #{body}"
        Logger.error(message)
        {:error, message}

      {:error, %HTTPoison.Error{} = error} ->
        message = "Cannot fetch macd data for ticker #{ticker}: #{HTTPoison.Error.message(error)}"
        Logger.error(message)
        {:error, message}
    end
  end

  def rsi(
        ticker,
        currency,
        from_datetime,
        to_datetime,
        aggregate_interval,
        rsi_interval,
        result_size_tail \\ 0
      ) do
    from_unix = DateTime.to_unix(from_datetime)
    to_unix = DateTime.to_unix(to_datetime)

    url = "#{tech_indicators_url()}/indicator/rsi"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"ticker", ticker},
        {"currency", currency},
        {"from_timestamp", from_unix},
        {"to_timestamp", to_unix},
        {"aggregate_interval", aggregate_interval},
        {"rsi_interval", rsi_interval},
        {"result_size_tail", result_size_tail}
      ]
    ]

    case @http_client.get(url, [], options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Poison.decode(body)

        result =
          result
          |> Enum.map(fn %{"timestamp" => timestamp, "rsi" => rsi} ->
            %{datetime: DateTime.from_unix!(timestamp), rsi: decimal_or_nil(rsi)}
          end)

        {:ok, result}

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        message = "Error status #{status} fetching rsi for ticker #{ticker}: #{body}"
        Logger.error(message)
        {:error, message}

      {:error, %HTTPoison.Error{} = error} ->
        message = "Cannot fetch rsi data for ticker #{ticker}: #{HTTPoison.Error.message(error)}"
        Logger.error(message)
        {:error, message}
    end
  end

  def price_volume_diff_ma(
        ticker,
        currency,
        from_datetime,
        to_datetime,
        aggregate_interval,
        window_type,
        approximation_window,
        comparison_window,
        result_size_tail \\ 0
      ) do
    from_unix = DateTime.to_unix(from_datetime)
    to_unix = DateTime.to_unix(to_datetime)

    url = "#{tech_indicators_url()}/indicator/pricevolumediff/ma"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"ticker", ticker},
        {"currency", currency},
        {"from_timestamp", from_unix},
        {"to_timestamp", to_unix},
        {"aggregate_interval", aggregate_interval},
        {"window_type", window_type},
        {"approximation_window", approximation_window},
        {"comparison_window", comparison_window},
        {"result_size_tail", result_size_tail}
      ]
    ]

    case @http_client.get(url, [], options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Poison.decode(body)

        result =
          result
          |> Enum.map(fn %{
                           "timestamp" => timestamp,
                           "price_volume_diff" => price_volume_diff,
                           "price_change" => price_change,
                           "volume_change" => volume_change
                         } ->
            %{
              datetime: DateTime.from_unix!(timestamp),
              price_volume_diff: decimal_or_nil(price_volume_diff),
              price_change: decimal_or_nil(price_change),
              volume_change: decimal_or_nil(volume_change)
            }
          end)

        {:ok, result}

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        message =
          "Error status #{status} fetching price-volume diff for ticker #{ticker}: #{body}"

        Logger.error(message)
        {:error, message}

      {:error, %HTTPoison.Error{} = error} ->
        message =
          "Cannot fetch price-volume diff data for ticker #{ticker}: #{
            HTTPoison.Error.message(error)
          }"

        Logger.error(message)
        {:error, message}
    end
  end

  def twitter_mention_count(
        ticker,
        from_datetime,
        to_datetime,
        aggregate_interval,
        result_size_tail \\ 0
      ) do
    from_unix = DateTime.to_unix(from_datetime)
    to_unix = DateTime.to_unix(to_datetime)

    url = "#{tech_indicators_url()}/indicator/twitter_mention_count"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"ticker", ticker},
        {"from_timestamp", from_unix},
        {"to_timestamp", to_unix},
        {"aggregate_interval", aggregate_interval},
        {"result_size_tail", result_size_tail}
      ]
    ]

    case @http_client.get(url, [], options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Poison.decode(body)

        result =
          result
          |> Enum.map(fn %{
                           "timestamp" => timestamp,
                           "mention_count" => mention_count
                         } ->
            %{
              datetime: DateTime.from_unix!(timestamp),
              mention_count: decimal_or_nil(mention_count)
            }
          end)

        {:ok, result}

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        message =
          "Error status #{status} fetching twitter mention count for ticker #{ticker}: #{body}"

        Logger.error(message)
        {:error, message}

      {:error, %HTTPoison.Error{} = error} ->
        message =
          "Cannot fetch twitter mention count data for ticker #{ticker}: #{
            HTTPoison.Error.message(error)
          }"

        Logger.error(message)
        {:error, message}
    end
  end

  defp decimal_or_nil(nil), do: nil
  defp decimal_or_nil(value), do: Decimal.new(value)

  defp tech_indicators_url() do
    Config.module_get(Sanbase.TechIndicators, :url)
  end
end
