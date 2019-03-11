defmodule Sanbase.TechIndicators do
  import Sanbase.Utils.ErrorHandling

  require Logger
  require Sanbase.Utils.Config, as: Config

  alias Sanbase.Model.Project

  require Mockery.Macro
  defp http_client, do: Mockery.Macro.mockable(HTTPoison)

  @recv_timeout 15_000

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
        {:ok, result} = Jason.decode(body)
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
        {:ok, result} = Jason.decode(body)
        emojis_sentiment_result(result)

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        error_result("Error status #{status} fetching emojis sentiment: #{body}")

      {:error, %HTTPoison.Error{} = error} ->
        error_result("Cannot fetch emojis sentiment data: #{HTTPoison.Error.message(error)}")
    end
  end

  def social_volume(
        slug,
        datetime_from,
        datetime_to,
        interval,
        social_volume_type
      ) do
    social_volume_request(
      slug,
      datetime_from,
      datetime_to,
      interval,
      social_volume_type
    )
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Jason.decode(body)
        social_volume_result(result)

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        warn_result("Error status #{status} fetching social volume for project #{slug}")

      {:error, %HTTPoison.Error{} = error} ->
        error_result(
          "Cannot fetch social volume data for project #{slug}: #{HTTPoison.Error.message(error)}"
        )
    end
  end

  def social_volume_projects() do
    social_volume_projects_request()
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Jason.decode(body)
        social_volume_projects_result(result)

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        warn_result("Error status #{status} fetching social volume projects.")

      {:error, %HTTPoison.Error{} = error} ->
        error_result(
          "Cannot fetch social volume projects data: #{HTTPoison.Error.message(error)}"
        )
    end
  end

  def topic_search(
        source,
        search_text,
        datetime_from,
        datetime_to,
        interval
      ) do
    topic_search_request(
      source,
      search_text,
      datetime_from,
      datetime_to,
      interval
    )
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Jason.decode(body)
        topic_search_result(result)

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        error_result(
          "Error status #{status} fetching results for search text \"#{search_text}\": #{body}"
        )

      {:error, %HTTPoison.Error{} = error} ->
        error_result(
          "Cannot fetch results for search text \"#{search_text}\": #{
            HTTPoison.Error.message(error)
          }"
        )
    end
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
         from_datetime,
         to_datetime,
         aggregate_interval,
         result_size_tail
       ) do
    from_unix = DateTime.to_unix(from_datetime)
    to_unix = DateTime.to_unix(to_datetime)

    url = "#{tech_indicators_url()}/indicator/summaryemojissentiment"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"from_timestamp", from_unix},
        {"to_timestamp", to_unix},
        {"aggregate_interval", aggregate_interval},
        {"result_size_tail", result_size_tail}
      ]
    ]

    http_client().get(url, [], options)
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

  defp social_volume_request(
         slug,
         datetime_from,
         datetime_to,
         interval,
         social_volume_type
       ) do
    from_unix = DateTime.to_unix(datetime_from)
    to_unix = DateTime.to_unix(datetime_to)
    ticker = Project.ticker_by_slug(slug)
    ticker_slug = "#{ticker}_#{slug}"

    url = "#{tech_indicators_url()}/indicator/#{social_volume_type}"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"project", ticker_slug},
        {"datetime_from", from_unix},
        {"datetime_to", to_unix},
        {"interval", interval}
      ]
    ]

    http_client().get(url, [], options)
  end

  defp social_volume_result(result) do
    result =
      result
      |> Enum.map(fn %{
                       "timestamp" => timestamp,
                       "mentions_count" => mentions_count
                     } ->
        %{
          datetime: DateTime.from_unix!(timestamp),
          mentions_count: mentions_count
        }
      end)

    {:ok, result}
  end

  defp social_volume_projects_request() do
    url = "#{tech_indicators_url()}/indicator/social_volume_projects"

    options = [recv_timeout: @recv_timeout]

    http_client().get(url, [], options)
  end

  defp social_volume_projects_result(result) do
    result =
      result
      |> Enum.map(fn ticker_slug ->
        String.split(ticker_slug, "_", parts: 2)
        |> Enum.at(1)
      end)

    {:ok, result}
  end

  defp topic_search_request(
         source,
         search_text,
         datetime_from,
         datetime_to,
         interval
       ) do
    from_unix = DateTime.to_unix(datetime_from)
    to_unix = DateTime.to_unix(datetime_to)

    url = "#{tech_indicators_url()}/indicator/topic_search"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"source", source},
        {"search_text", search_text},
        {"from_timestamp", from_unix},
        {"to_timestamp", to_unix},
        {"interval", interval}
      ]
    ]

    http_client().get(url, [], options)
  end

  defp topic_search_result(%{"messages" => messages, "chart_data" => chart_data}) do
    messages = parse_topic_search_data(messages, "text")
    chart_data = parse_topic_search_data(chart_data, "mentions_count")

    result = %{messages: messages, chart_data: chart_data}

    {:ok, result}
  end

  defp parse_topic_search_data(data, key) do
    data
    |> Enum.map(fn result ->
      %{
        :datetime => Map.get(result, "timestamp") |> DateTime.from_unix!(),
        String.to_atom(key) => Map.get(result, key)
      }
    end)
  end

  defp tech_indicators_url() do
    Config.module_get(Sanbase.TechIndicators, :url)
  end
end
