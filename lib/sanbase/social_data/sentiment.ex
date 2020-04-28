defmodule Sanbase.SocialData.Sentiment do
  import Sanbase.Utils.ErrorHandling

  require Logger
  require Sanbase.Utils.Config, as: Config

  alias Sanbase.Model.Project
  alias Sanbase.Model.Project.SocialVolumeQuery

  require Mockery.Macro
  defp http_client, do: Mockery.Macro.mockable(HTTPoison)

  @recv_timeout 25_000
  @sources [:telegram, :professional_traders_chat, :reddit, :discord]

  def sentiment(selector, from, to, interval, source, column)
      when source in [:all, "all", :total, "total"] do
    result =
      @sources
      |> Sanbase.Parallel.flat_map(
        fn source ->
          {:ok, result} = sentiment(selector, from, to, interval, source, column)
          result
        end,
        max_concurency: 4
      )
      |> Sanbase.Utils.Transform.sum_by_datetime(:positive_sentiment)
      # COLUMN VALUE TODO

    {:ok, result}
  end

  def sentiment(selector, from, to, interval, source, column) do
    sentiment_request(selector, from, to, interval, source, column)
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Jason.decode(body)
        sentiment_result(result, column)

      {:ok, %HTTPoison.Response{status_code: status}} ->
        warn_result("Error status #{status} fetching sentiment #{column} for project #{slug}")

      {:error, %HTTPoison.Error{} = error} ->
        error_result(
          "Cannot fetch sentiment #{column} data for project #{slug}: #{HTTPoison.Error.message(error)}"
        )
    end
  end

  defp sentiment_request(selector, from, to, interval, source, column) do
    {"search_text", search_text} = sentiment_selector_handler(selector, from, to, interval, source)

    url = "#{metrics_hub_url()}/sentiment_#{column}"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"search_text", search_text},
        {"from_timestamp", from |> DateTime.to_iso8601()},
        {"to_timestamp", to |> DateTime.to_iso8601()},
        {"interval", interval},
        {"source", source}
      ]
    ]

    http_client().get(url, [], options)
  end

  defp sentiment_selector_handler(%{slug: slug}) do
    slug
    |> Project.by_slug(only_preload: [:social_volume_query])
    |> case do
      %Project{social_volume_query: %{query: query_text}}
      when not is_nil(query_text) ->
        {"search_text", query_text}

      %Project{} = project ->
        {"search_text", SocialVolumeQuery.default_query(project)}

      _ ->
        {:error, "Invalid slug"}
    end
  end

  defp sentiment_selector_handler(%{text: search_text}) do
    {"search_text", search_text}
  end

  defp sentiment_result(%{"data" => map}, column) do
    # COLUMN VALUE TODO
    map =
      Enum.map(map, fn {datetime, value} ->
        %{
          datetime: Sanbase.DateTimeUtils.from_iso8601!(datetime),
          positive_sentiment: value
        }
      end)
      |> Enum.sort_by(& &1.datetime, {:asc, DateTime})

    {:ok, map}
  end

  defp metrics_hub_url() do
    Config.module_get(Sanbase.SocialData, :metricshub_url)
  end
end
