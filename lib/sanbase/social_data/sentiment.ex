defmodule Sanbase.SocialData.Sentiment do
  import Sanbase.Utils.ErrorHandling
  import Sanbase.SocialData.Utils, only: [maybe_add_and_rename_field: 4]

  alias Sanbase.Utils.Config
  alias Sanbase.SocialData.SocialHelper

  require Logger

  require Mockery.Macro
  defp http_client, do: Mockery.Macro.mockable(HTTPoison)

  @recv_timeout 25_000

  @supported_sentiment_types [
    "positive",
    "negative",
    "balance",
    "volume_consumed",
    "weighted",
    "bearish",
    "bullish",
    "neutral"
  ]
  def supported_sentiment_types(), do: @supported_sentiment_types

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
        params:
          [
            {selector_name, selector_value},
            {"from_timestamp", from |> DateTime.truncate(:second) |> DateTime.to_iso8601()},
            {"to_timestamp", to |> DateTime.truncate(:second) |> DateTime.to_iso8601()},
            {"interval", interval},
            {"source", source}
          ]
          |> maybe_add_and_rename_field(selector, :only_project_channels, "project")
          |> maybe_add_and_rename_field(selector, :only_project_channels_spec, "project_spec")
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
