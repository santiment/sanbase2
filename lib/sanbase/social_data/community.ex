defmodule Sanbase.SocialData.Community do
  import Sanbase.Utils.ErrorHandling

  alias Sanbase.Utils.Config

  alias Sanbase.Project

  require Logger
  require Mockery.Macro

  defp http_client, do: Mockery.Macro.mockable(HTTPoison)

  @recv_timeout 25_000
  @sources [:telegram, :reddit]

  def community_messages_count(selector, from, to, interval, source)
      when source in [:all, "all", :total, "total"] do
    result =
      @sources
      |> Sanbase.Parallel.flat_map(
        fn source ->
          {:ok, result} = community_messages_count(selector, from, to, interval, source)
          result
        end,
        max_concurrency: 4
      )
      |> Sanbase.Utils.Transform.sum_by_datetime(:mentions_count)

    {:ok, result}
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
          "Cannot fetch community messages count data for project #{slug}: #{HTTPoison.Error.message(error)}"
        )
    end
  end

  def community_messages_count(argument) do
    {:error, "Invalid argument for community_messages_count #{inspect(argument)}"}
  end

  defp community_messages_count_request(slug, from, to, interval, source) do
    url = "#{metrics_hub_url()}/social_volume_unit"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"slugs", slug},
        {"from_timestamp", from |> DateTime.truncate(:second) |> DateTime.to_iso8601()},
        {"to_timestamp", to |> DateTime.truncate(:second) |> DateTime.to_iso8601()},
        {"interval", interval},
        {"source", to_string(source)},
        {"search_text", "*"},
        {"include_units", "own"}
      ]
    ]

    http_client().get(url, [], options)
  end

  defp community_messages_count_result(%{"data" => data}) do
    result =
      data
      |> Enum.map(fn {timestamp, value} ->
        %{
          datetime: Sanbase.DateTimeUtils.from_iso8601!(timestamp),
          mentions_count: value
        }
      end)
      |> Enum.sort_by(& &1.datetime, {:asc, DateTime})

    {:ok, result}
  end

  defp community_messages_count_result(%{"error" => %{"message" => error_msg}}) do
    {:error, "Error fetching community messages count. Reason: #{error_msg}"}
  end

  defp community_messages_count_result(result) do
    Logger.error("Unexpected community messages count result: #{inspect(result)}")
    {:error, "Error fetching community messages count."}
  end

  defp metrics_hub_url() do
    Config.module_get(Sanbase.SocialData, :metricshub_url)
  end
end
