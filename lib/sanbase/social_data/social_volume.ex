defmodule Sanbase.SocialData.SocialVolume do
  import Sanbase.Utils.ErrorHandling

  require Logger
  require Sanbase.Utils.Config, as: Config

  alias Sanbase.SocialData.SocialHelper
  alias Sanbase.Model.Project

  require Mockery.Macro
  defp http_client, do: Mockery.Macro.mockable(HTTPoison)

  @recv_timeout 25_000

  def social_volume(selector, from, to, interval, source)
      when source in [:all, "all", :total, "total"] do
    sources_string = SocialHelper.sources() |> Enum.join(",")

    social_volume(selector, from, to, interval, sources_string)
  end

  def social_volume(selector, from, to, interval, source) do
    social_volume_request(selector, from, to, interval, source)
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Jason.decode(body)
        social_volume_result(result)

      {:ok, %HTTPoison.Response{status_code: status}} ->
        warn_result("Error status #{status} fetching social volume for #{inspect(selector)}")

      {:error, %HTTPoison.Error{} = error} ->
        error_result(
          "Cannot fetch social volume data for #{inspect(selector)}: #{
            HTTPoison.Error.message(error)
          }"
        )

      {:error, error} ->
        {:error, error}
    end
  end

  def social_volume_projects() do
    {:ok, Project.List.projects()}
  end

  defp social_volume_request(selector, from, to, interval, source) do
    with {:ok, search_text} <- SocialHelper.social_metrics_selector_handler(selector) do
      url = "#{metrics_hub_url()}/social_volume"

      options = [
        recv_timeout: @recv_timeout,
        params: [
          {"search_text", search_text},
          {"from_timestamp", from |> DateTime.truncate(:second) |> DateTime.to_iso8601()},
          {"to_timestamp", to |> DateTime.truncate(:second) |> DateTime.to_iso8601()},
          {"interval", interval},
          {"source", source}
        ]
      ]

      http_client().get(url, [], options)
    end
  end

  defp social_volume_result(%{"data" => map}) do
    map =
      Enum.map(map, fn {datetime, value} ->
        %{
          datetime: Sanbase.DateTimeUtils.from_iso8601!(datetime),
          mentions_count: value
        }
      end)
      |> Enum.sort_by(& &1.datetime, {:asc, DateTime})

    {:ok, map}
  end

  defp metrics_hub_url() do
    Config.module_get(Sanbase.SocialData, :metricshub_url)
  end
end
