defmodule Sanbase.SocialData.SocialVolume do
  import Sanbase.Utils.ErrorHandling

  require Logger
  require Sanbase.Utils.Config, as: Config

  alias Sanbase.Model.Project

  require Mockery.Macro
  defp http_client, do: Mockery.Macro.mockable(HTTPoison)

  @recv_timeout 15_000
  @sources [:telegram, :professional_traders_chat, :reddit, :discord]

  def social_volume(slug, from, to, interval, source)
      when source in [:all, "all", :total, "total"] do
    result =
      @sources
      |> Sanbase.Parallel.map(
        fn source ->
          {:ok, result} = social_volume(slug, from, to, interval, source)
          result
        end,
        max_concurrency: 4
      )
      |> List.zip()
      |> Enum.map(&Tuple.to_list/1)
      |> Enum.map(fn all_sources_point ->
        total_mentions_count = all_sources_point |> Enum.reduce(0, &(&2 + &1.mentions_count))

        %{
          datetime: all_sources_point |> List.first() |> Map.get(:datetime),
          mentions_count: total_mentions_count
        }
      end)

    {:ok, result}
  end

  def social_volume(slug, from, to, interval, source) do
    social_volume_request(slug, from, to, interval, source)
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Jason.decode(body)
        social_volume_result(result)

      {:ok, %HTTPoison.Response{status_code: status}} ->
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

      {:ok, %HTTPoison.Response{status_code: status}} ->
        warn_result("Error status #{status} fetching social volume projects.")

      {:error, %HTTPoison.Error{} = error} ->
        error_result(
          "Cannot fetch social volume projects data: #{HTTPoison.Error.message(error)}"
        )
    end
  end

  def topic_search(source, search_text, from, to, interval) do
    topic_search_request(source, search_text, from, to, interval)
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

  defp source_to_indicator(<<"reddit", _::binary>>), do: "reddit_comments_overview"
  defp source_to_indicator(<<"discord", _::binary>>), do: "discord_chats_overview"
  defp source_to_indicator(<<"telegram", _::binary>>), do: "telegram_chats_overview"

  defp source_to_indicator(<<"professional_traders_chat", _::binary>>),
    do: "professional_traders_chat_overview"

  defp social_volume_request(slug, from, to, interval, source) do
    url = "#{tech_indicators_url()}/indicator/#{source_to_indicator(source |> to_string())}"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"project", "#{Project.ticker_by_slug(slug)}_#{slug}"},
        {"datetime_from", DateTime.to_unix(from)},
        {"datetime_to", DateTime.to_unix(to)},
        {"interval", interval}
      ]
    ]

    http_client().get(url, [], options)
  end

  defp social_volume_result(result) do
    result =
      result
      |> Enum.map(fn
        %{"timestamp" => timestamp, "mentions_count" => mentions_count} ->
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
        [_ticker, slug] = String.split(ticker_slug, "_", parts: 2)
        slug
      end)

    {:ok, result}
  end

  defp topic_search_request(source, search_text, from, to, interval) do
    url = "#{tech_indicators_url()}/indicator/topic_search"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"source", source},
        {"search_text", search_text},
        {"from_timestamp", DateTime.to_unix(from)},
        {"to_timestamp", DateTime.to_unix(to)},
        {"interval", interval}
      ]
    ]

    http_client().get(url, [], options)
  end

  defp topic_search_result(%{"messages" => messages, "chart_data" => chart_data}) do
    messages = parse_topic_search_data(messages, :text)
    chart_data = parse_topic_search_data(chart_data, :mentions_count)

    result = %{messages: messages, chart_data: chart_data}

    {:ok, result}
  end

  defp parse_topic_search_data(data, key) do
    data
    |> Enum.map(fn result ->
      %{
        :datetime => Map.get(result, "timestamp") |> DateTime.from_unix!(),
        key => Map.get(result, to_string(key))
      }
    end)
  end

  defp tech_indicators_url() do
    Config.module_get(Sanbase.TechIndicators, :url)
  end
end
