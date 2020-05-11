defmodule Sanbase.SocialData.Sentiment do
  import Sanbase.Utils.ErrorHandling

  require Logger
  require Sanbase.Utils.Config, as: Config

  alias Sanbase.SocialData.SocialHelper

  require Mockery.Macro
  defp http_client, do: Mockery.Macro.mockable(HTTPoison)

  @recv_timeout 25_000
  @sources [:telegram, :professional_traders_chat, :reddit, :discord, :twitter, :bitcointalk]

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
      |> Sanbase.Utils.Transform.sum_by_datetime(:value)

    {:ok, result}
  end

  def sentiment(selector, from, to, interval, source, column) do
    sentiment_request(selector, from, to, interval, source, column)
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Jason.decode(body)
        sentiment_result(result)

      {:ok, %HTTPoison.Response{status_code: status}} ->
        warn_result(
          "Error status #{status} fetching sentiment #{column} for #{inspect(selector)}"
        )

      {:error, %HTTPoison.Error{} = error} ->
        error_result(
          "Cannot fetch sentiment #{column} data for #{inspect(selector)}: #{
            HTTPoison.Error.message(error)
          }"
        )

      {:error, error} ->
        {:error, error}
    end
  end

  defp sentiment_request(selector, from, to, interval, source, column) do
    with {:ok, search_text} <- SocialHelper.social_metrics_selector_handler(selector) do
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
  end

  defp sentiment_result(%{"data" => map}) do
    map =
      Enum.map(map, fn {datetime, value} ->
        %{
          datetime: Sanbase.DateTimeUtils.from_iso8601!(datetime),
          value: value
        }
      end)
      |> Enum.sort_by(& &1.datetime, {:asc, DateTime})

    {:ok, map}
  end

  defp metrics_hub_url() do
    Config.module_get(Sanbase.SocialData, :metricshub_url)
  end
end
