defmodule Sanbase.SocialData.SocialVolume do
  import Sanbase.Utils.ErrorHandling

  require Logger
  require Sanbase.Utils.Config, as: Config

  alias Sanbase.Model.Project

  require Mockery.Macro
  defp http_client, do: Mockery.Macro.mockable(HTTPoison)

  @recv_timeout 25_000
  @sources [:telegram, :professional_traders_chat, :reddit, :discord]

  def social_volume(slug, from, to, interval, source)
      when source in [:all, "all", :total, "total"] do
    result =
      @sources
      |> Sanbase.Parallel.flat_map(
        fn source ->
          {:ok, result} = social_volume(slug, from, to, interval, source)
          result
        end,
        max_concurrency: 4
      )
      |> Sanbase.Utils.Transform.sum_by_datetime(:mentions_count)

    {:ok, result}
  end

  def social_volume(slug, from, to, interval, source) do
    social_volume_request(%{slug: slug}, from, to, interval, source)
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

  def topic_search(search_text, from, to, interval, source)
      when source in [:all, "all", :total, "total"] do
    result =
      @sources
      |> Sanbase.Parallel.flat_map(
        fn source ->
          {:ok, result} = topic_search(search_text, from, to, interval, source)
          result
        end,
        max_concurrency: 4
      )
      |> Sanbase.Utils.Transform.sum_by_datetime(:mentions_count)

    {:ok, result}
  end

  def topic_search(search_text, from, to, interval, source) do
    social_volume_request(%{search_text: search_text}, from, to, interval, source)
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Jason.decode(body)
        social_volume_result(result)

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

  defp social_volume_request(selector, from, to, interval, source) do
    option =
      case selector do
        %{slug: slug} ->
          {"slug", "#{slug}"}

        %{search_text: search_text} ->
          {"search_text", search_text}

        {:error, error} ->
          error
      end

    url =
      "#{metrics_hub_url()}/social_volume?from_timestamp=#{from}&to_timestamp=#{to}&interval=#{
        interval
      }&source=#{source}"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        option
      ]
    ]

    http_client().get(url, [], options)
  end

  defp social_volume_result(result) do
    %{"data" => map} = result

    map =
      Map.to_list(map)
      |> Enum.map(fn {timestamp, value} ->
        {:ok, datetime, _status} = DateTime.from_iso8601(timestamp)

        %{
          datetime: datetime,
          mentions_count: value
        }
      end)

    {:ok, map}
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

  defp tech_indicators_url() do
    Config.module_get(Sanbase.TechIndicators, :url)
  end

  defp metrics_hub_url() do
    Config.module_get(Sanbase.SocialData, :metricshub_url)
  end
end
