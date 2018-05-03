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
    macd_request(
      ticker,
      currency,
      from_datetime,
      to_datetime,
      aggregate_interval,
      result_size_tail
    )
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Poison.decode(body)

        macd_result(result)

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        error_result("Error status #{status} fetching macd for ticker #{ticker}: #{body}")

      {:error, %HTTPoison.Error{} = error} ->
        error_result(
          "Cannot fetch macd data for ticker #{ticker}: #{HTTPoison.Error.message(error)}"
        )
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
    rsi_request(
      ticker,
      currency,
      from_datetime,
      to_datetime,
      aggregate_interval,
      rsi_interval,
      result_size_tail
    )
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Poison.decode(body)

        rsi_result(result)

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        error_result("Error status #{status} fetching rsi for ticker #{ticker}: #{body}")

      {:error, %HTTPoison.Error{} = error} ->
        error_result(
          "Cannot fetch rsi data for ticker #{ticker}: #{HTTPoison.Error.message(error)}"
        )
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
    price_volume_diff_ma_request(
      ticker,
      currency,
      from_datetime,
      to_datetime,
      aggregate_interval,
      window_type,
      approximation_window,
      comparison_window,
      result_size_tail
    )
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Poison.decode(body)

        price_volume_diff_ma_result(result)

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        error_result(
          "Error status #{status} fetching price-volume diff for ticker #{ticker}: #{body}"
        )

      {:error, %HTTPoison.Error{} = error} ->
        error_result(
          "Cannot fetch price-volume diff data for ticker #{ticker}: #{
            HTTPoison.Error.message(error)
          }"
        )
    end
  end

  def twitter_mention_count(
        ticker,
        from_datetime,
        to_datetime,
        aggregate_interval,
        result_size_tail \\ 0
      ) do
    twitter_mention_count_request(
      ticker,
      from_datetime,
      to_datetime,
      aggregate_interval,
      result_size_tail
    )
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Poison.decode(body)
        twitter_mention_count_result(result)

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        error_result(
          "Error status #{status} fetching twitter mention count for ticker #{ticker}: #{body}"
        )

      {:error, %HTTPoison.Error{} = error} ->
        error_result(
          "Cannot fetch twitter mention count data for ticker #{ticker}: #{
            HTTPoison.Error.message(error)
          }"
        )
    end
  end

  def emojis_sentiment(
        from_datetime,
        to_datetime,
        aggregate_interval,
        result_size_tail \\ 0
      ) do
    emojis_sentiment_request(
      from_datetime,
      to_datetime,
      aggregate_interval,
      result_size_tail
    )
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Poison.decode(body)
        emojis_sentiment_result(result)

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        error_result("Error status #{status} fetching emojis sentiment: #{body}")

      {:error, %HTTPoison.Error{} = error} ->
        error_result("Cannot fetch emojis sentiment data: #{HTTPoison.Error.message(error)}")
    end
  end

  defp macd_request(
         ticker,
         currency,
         from_datetime,
         to_datetime,
         aggregate_interval,
         result_size_tail
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

    @http_client.get(url, [], options)
  end

  defp macd_result(result) do
    result =
      result
      |> Enum.map(fn %{"timestamp" => timestamp, "macd" => macd} ->
        %{datetime: DateTime.from_unix!(timestamp), macd: macd}
      end)

    {:ok, result}
  end

  defp rsi_request(
         ticker,
         currency,
         from_datetime,
         to_datetime,
         aggregate_interval,
         rsi_interval,
         result_size_tail
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

    @http_client.get(url, [], options)
  end

  defp rsi_result(result) do
    result =
      result
      |> Enum.map(fn %{"timestamp" => timestamp, "rsi" => rsi} ->
        %{datetime: DateTime.from_unix!(timestamp), rsi: rsi}
      end)

    {:ok, result}
  end

  defp price_volume_diff_ma_request(
         ticker,
         currency,
         from_datetime,
         to_datetime,
         aggregate_interval,
         window_type,
         approximation_window,
         comparison_window,
         result_size_tail
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

    @http_client.get(url, [], options)
  end

  defp price_volume_diff_ma_result(result) do
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
          price_volume_diff: price_volume_diff,
          price_change: price_change,
          volume_change: volume_change
        }
      end)

    {:ok, result}
  end

  defp twitter_mention_count_request(
         ticker,
         from_datetime,
         to_datetime,
         aggregate_interval,
         result_size_tail
       ) do
    from_unix = DateTime.to_unix(from_datetime)
    to_unix = DateTime.to_unix(to_datetime)

    url = "#{tech_indicators_url()}/indicator/twittermentioncount"

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

    @http_client.get(url, [], options)
  end

  defp twitter_mention_count_result(result) do
    result =
      result
      |> Enum.map(fn %{
                       "timestamp" => timestamp,
                       "mention_count" => mention_count
                     } ->
        %{
          datetime: DateTime.from_unix!(timestamp),
          mention_count: mention_count
        }
      end)

    {:ok, result}
  end

  defp emojis_sentiment_request(
         from_datetime,
         to_datetime,
         aggregate_interval,
         result_size_tail
       ) do
    from_unix = DateTime.to_unix(from_datetime)
    to_unix = DateTime.to_unix(to_datetime)

    url = "#{tech_indicators_url()}/indicator/emojissentiment"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"from_timestamp", from_unix},
        {"to_timestamp", to_unix},
        {"aggregate_interval", aggregate_interval},
        {"result_size_tail", result_size_tail}
      ]
    ]

    @http_client.get(url, [], options)
  end

  defp emojis_sentiment_result(result) do
    result =
      result
      |> Enum.map(fn %{
                       "timestamp" => timestamp,
                       "sentiment" => sentiment
                     } ->
        %{
          datetime: DateTime.from_unix!(timestamp),
          sentiment: sentiment
        }
      end)

    {:ok, result}
  end

  defp error_result(message) do
    log_id = Ecto.UUID.generate()
    Logger.error("[#{log_id}] #{message}")
    {:error, "[#{log_id}] Error executing query. See logs for details."}
  end

  defp tech_indicators_url() do
    Config.module_get(Sanbase.TechIndicators, :url)
  end
end
