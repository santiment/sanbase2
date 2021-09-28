defmodule Sanbase.TechIndicators do
  import Sanbase.Utils.ErrorHandling

  require Logger
  alias Sanbase.Utils.Config

  require Mockery.Macro
  defp http_client, do: Mockery.Macro.mockable(HTTPoison)

  @recv_timeout 15_000

  def twitter_mention_count(ticker, from, to, interval, result_size_tail \\ 0) do
    twitter_mention_count_request(ticker, from, to, interval, result_size_tail)
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Jason.decode(body)
        twitter_mention_count_result(result)

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        error_result(
          "Error status #{status} fetching twitter mention count for ticker #{ticker}: #{body}"
        )

      {:error, %HTTPoison.Error{} = error} ->
        error_result(
          "Cannot fetch twitter mention count data for ticker #{ticker}: #{HTTPoison.Error.message(error)}"
        )
    end
  end

  def emojis_sentiment(from, to, interval, result_size_tail \\ 0) do
    emojis_sentiment_request(from, to, interval, result_size_tail)
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Jason.decode(body)
        emojis_sentiment_result(result)

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        error_result("Error status #{status} fetching emojis sentiment: #{body}")

      {:error, %HTTPoison.Error{} = error} ->
        error_result("Cannot fetch emojis sentiment data: #{HTTPoison.Error.message(error)}")
    end
  end

  defp twitter_mention_count_request(ticker, from, to, interval, result_size_tail) do
    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)

    url = "#{tech_indicators_url()}/indicator/twittermentioncount"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"ticker", ticker},
        {"from_timestamp", from_unix},
        {"to_timestamp", to_unix},
        {"interval", interval},
        {"result_size_tail", result_size_tail}
      ]
    ]

    http_client().get(url, [], options)
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
         from,
         to,
         interval,
         result_size_tail
       ) do
    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)

    url = "#{tech_indicators_url()}/indicator/summaryemojissentiment"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"from_timestamp", from_unix},
        {"to_timestamp", to_unix},
        {"interval", interval},
        {"result_size_tail", result_size_tail}
      ]
    ]

    http_client().get(url, [], options)
  end

  defp emojis_sentiment_result(result) do
    result =
      result
      |> Enum.map(fn
        %{"timestamp" => timestamp, "sentiment" => sentiment} ->
          %{
            datetime: DateTime.from_unix!(timestamp),
            sentiment: sentiment
          }
      end)

    {:ok, result}
  end

  defp tech_indicators_url() do
    Config.module_get(Sanbase.TechIndicators, :url)
  end
end
