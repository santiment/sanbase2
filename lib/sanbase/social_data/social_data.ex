defmodule Sanbase.SocialData do
  import Sanbase.Utils.ErrorHandling, only: [error_result: 1]

  require Logger
  require Sanbase.Utils.Config, as: Config

  require Mockery.Macro
  defp http_client, do: Mockery.Macro.mockable(HTTPoison)

  @recv_timeout 15_000

  def trending_words(
        source,
        size,
        hour,
        from_datetime,
        to_datetime
      ) do
    trending_words_request(
      source,
      size,
      hour,
      from_datetime,
      to_datetime
    )
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Jason.decode(body)

        trending_words_result(result)

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        error_result(
          "Error status #{status} fetching trending words for source: #{source}: #{body}"
        )

      {:error, %HTTPoison.Error{} = error} ->
        error_result(
          "Cannot fetch trending words data for source #{source}: #{
            HTTPoison.Error.message(error)
          }"
        )
    end
  end

  def word_context(
        word,
        source,
        size,
        from_datetime,
        to_datetime
      ) do
    word_context_request(
      word,
      source,
      size,
      from_datetime,
      to_datetime
    )
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Jason.decode(body)
        word_context_result(result)

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        error_result("Error status #{status} fetching context for word #{word}: #{body}")

      {:error, %HTTPoison.Error{} = error} ->
        error_result("Cannot fetch context for word #{word}: #{HTTPoison.Error.message(error)}")
    end
  end

  def word_trend_score(
        word,
        source,
        from_datetime,
        to_datetime
      ) do
    word_trend_score_request(
      word,
      source,
      from_datetime,
      to_datetime
    )
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Jason.decode(body)
        word_trend_score_result(result)

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        error_result("Error status #{status} fetching word_trend_score for word #{word}: #{body}")

      {:error, %HTTPoison.Error{} = error} ->
        error_result(
          "Cannot fetch word_trend_score for word #{word}: #{HTTPoison.Error.message(error)}"
        )
    end
  end

  def social_gainers_losers(%{
        status: status,
        from: from,
        to: to,
        interval: interval,
        size: size
      }) do
    social_gainers_losers_request(status, from, to, interval, size)
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        Jason.decode!(body)

      {:error, %HTTPoison.Error{} = error} ->
        {:error, error}
    end
  end

  defp social_gainers_losers_request(
         status,
         from_datetime,
         to_datetime,
         interval,
         size
       ) do
    from_unix = DateTime.to_unix(from_datetime)
    to_unix = DateTime.to_unix(to_datetime)

    url = "#{tech_indicators_url()}/indicator/social_gainers_losers"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"status", status |> Atom.to_string()},
        {"from_timestamp", from_unix},
        {"to_timestamp", to_unix},
        {"range", interval},
        {"size", size}
      ]
    ]

    http_client().get(url, [], options)
  end

  def social_gainers_losers_for_project() do
  end

  defp trending_words_request(
         source,
         size,
         hour,
         from_datetime,
         to_datetime
       ) do
    from_unix = DateTime.to_unix(from_datetime)
    to_unix = DateTime.to_unix(to_datetime)

    url = "#{tech_indicators_url()}/indicator/trending_words"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"source", source |> Atom.to_string()},
        {"n", size},
        {"hour", hour},
        {"from_timestamp", from_unix},
        {"to_timestamp", to_unix}
      ]
    ]

    http_client().get(url, [], options)
  end

  defp trending_words_result(result) do
    result =
      result
      |> Enum.map(fn %{"timestamp" => timestamp, "top_words" => top_words} ->
        %{
          datetime: DateTime.from_unix!(timestamp),
          top_words:
            top_words
            |> Enum.map(fn {k, v} ->
              %{word: k, score: v}
            end)
        }
      end)

    {:ok, result}
  end

  defp word_context_request(
         word,
         source,
         size,
         from_datetime,
         to_datetime
       ) do
    from_unix = DateTime.to_unix(from_datetime)
    to_unix = DateTime.to_unix(to_datetime)

    url = "#{tech_indicators_url()}/indicator/word_context"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"word", word},
        {"size", size},
        {"source", source |> Atom.to_string()},
        {"from_timestamp", from_unix},
        {"to_timestamp", to_unix}
      ]
    ]

    http_client().get(url, [], options)
  end

  defp word_trend_score_request(
         word,
         source,
         from_datetime,
         to_datetime
       ) do
    from_unix = DateTime.to_unix(from_datetime)
    to_unix = DateTime.to_unix(to_datetime)

    url = "#{tech_indicators_url()}/indicator/word_trend_score"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"word", word},
        {"source", source |> Atom.to_string()},
        {"from_timestamp", from_unix},
        {"to_timestamp", to_unix}
      ]
    ]

    http_client().get(url, [], options)
  end

  defp word_context_result(result) do
    result =
      result
      |> Enum.map(fn {k, v} -> %{word: k, score: v["score"]} end)
      |> Enum.sort(&(&1.score >= &2.score))

    {:ok, result}
  end

  defp word_trend_score_result(result) do
    result =
      result
      |> Enum.map(fn %{
                       "timestamp" => timestamp,
                       "score" => score,
                       "hour" => hour,
                       "source" => source
                     } ->
        %{
          datetime: combine_unix_dt_and_hour(timestamp, hour),
          score: score,
          source: String.to_existing_atom(source)
        }
      end)
      |> Enum.sort(&(&1.score >= &2.score))

    {:ok, result}
  end

  defp tech_indicators_url() do
    Config.module_get(Sanbase.TechIndicators, :url)
  end

  def combine_unix_dt_and_hour(unix_dt, hour) do
    unix_dt
    |> DateTime.from_unix!()
    |> Timex.beginning_of_day()
    |> Timex.shift(hours: Sanbase.Math.to_integer(hour))
  end
end
