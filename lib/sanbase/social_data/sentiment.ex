defmodule Sanbase.SocialData.Sentiment do
  import Sanbase.Utils.ErrorHandling

  require Logger
  alias Sanbase.Utils.Config

  alias Sanbase.SocialData.SocialHelper

  require Mockery.Macro
  defp http_client, do: Mockery.Macro.mockable(HTTPoison)

  @recv_timeout 25_000

  def sentiment(selector, from, to, interval, source, type)
      when source in [:all, "all", :total] do
    sentiment(selector, from, to, interval, SocialHelper.sources_total_string(), type)
  end

  def sentiment(selector, from, to, interval, source, type) do
    case sentiment_request(selector, from, to, interval, source, type) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Jason.decode(body)
        sentiment_result(result)

      {:ok, %HTTPoison.Response{status_code: status}} ->
        warn_result("Error status #{status} fetching sentiment #{type} for #{inspect(selector)}")

      {:error, %HTTPoison.Error{} = error} ->
        error_result(
          "Cannot fetch sentiment #{type} data for #{inspect(selector)}: #{HTTPoison.Error.message(error)}"
        )

      {:error, error} ->
        {:error, error}
    end
  end

  defp sentiment_request(selector, from, to, interval, source, type) do
    with {:ok, selector_name, selector_value} <-
           SocialHelper.social_metrics_selector_handler(selector) do
      url = "#{metrics_hub_url()}/sentiment_#{type}"

      options = [
        recv_timeout: @recv_timeout,
        params: [
          {selector_name, selector_value},
          {"from_timestamp", from |> DateTime.truncate(:second) |> DateTime.to_iso8601()},
          {"to_timestamp", to |> DateTime.truncate(:second) |> DateTime.to_iso8601()},
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
