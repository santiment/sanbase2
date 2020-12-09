defmodule Sanbase.SocialData.Community do
  import Sanbase.Utils.ErrorHandling

  alias Sanbase.SocialData.SocialHelper

  require Sanbase.Utils.Config, as: Config

  alias Sanbase.Model.Project

  require Mockery.Macro
  defp http_client, do: Mockery.Macro.mockable(HTTPoison)

  @recv_timeout 25_000

  def community_messages_count(selector, from, to, interval, source)
      when source in [:all, "all", :total, "total"] do
    sources_string = SocialHelper.sources() |> Enum.join(",")

    community_messages_count(selector, from, to, interval, sources_string)
  end

  def community_messages_count(%{slug: slug}, from, to, interval, source) do
    community_messages_count_request(slug, from, to, interval, source |> to_string())
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Jason.decode(body)
        community_messages_count_result(result)

      {:ok, %HTTPoison.Response{status_code: status}} ->
        warn_result(
          "Error status #{status} fetching community messages count for project #{slug}"
        )

      {:error, %HTTPoison.Error{} = error} ->
        error_result(
          "Cannot fetch community messages count data for project #{slug}: #{
            HTTPoison.Error.message(error)
          }"
        )

      {:error, error} ->
        {:error, error}
    end
  end

  defp community_messages_count_request(slug, from, to, interval, source) do
    url = "#{metrics_hub_url()}/community_social_volume"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"slug", slug},
        {"from_timestamp", from |> DateTime.truncate(:second) |> DateTime.to_iso8601()},
        {"to_timestamp", to |> DateTime.truncate(:second) |> DateTime.to_iso8601()},
        {"interval", interval},
        {"source", source}
      ]
    ]

    http_client().get(url, [], options)
  end

  defp community_messages_count_result(%{"data" => map}) do
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
