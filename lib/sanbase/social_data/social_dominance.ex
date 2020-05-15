defmodule Sanbase.SocialData.SocialDominance do
  import Sanbase.Utils.ErrorHandling
  import Sanbase.DateTimeUtils, only: [round_datetime: 1]

  alias Sanbase.Model.Project
  alias Sanbase.Cache

  require Mockery.Macro

  require Sanbase.Utils.Config, as: Config
  require SanbaseWeb.Graphql.Schema

  @recv_timeout 15_000
  @sources [:telegram, :professional_traders_chat, :reddit, :discord, :twitter, :bitcointalk]

  def social_dominance(%{slug: slug}, from, to, interval, source)
      when source in [:all, "all", :total, "total"] do
    result =
      @sources
      |> Sanbase.Parallel.flat_map(
        fn source ->
          case social_dominance_request(slug, from, to, interval, source |> to_string()) do
            {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
              {:ok, result} = Jason.decode(body)

              %{"data" => map} = result

              Enum.map(map, fn {datetime, value} ->
                {Sanbase.DateTimeUtils.from_iso8601!(datetime), (value * 100) |> Float.round(2)}
              end)

            _ ->
              []
          end
        end,
        max_concurrency: 4
      )
      |> Enum.group_by(fn {datetime, _} -> datetime end, fn {_, data} -> data end)
      |> Enum.map(fn {datetime, maps_list} ->
        dominance = Enum.sum(maps_list) / length(@sources)
        {datetime, dominance |> Float.round(2)}
      end)
      |> Enum.map(fn {datetime, dominance} ->
        %{
          datetime: datetime,
          dominance: dominance
        }
      end)
      |> Enum.sort_by(&DateTime.to_unix(&1.datetime))

    {:ok, result}
  end

  def social_dominance(%{text: text}, from, to, interval, source) do
    with {:ok, text_volume} <-
           Sanbase.SocialData.social_volume(%{text: text}, from, to, interval, source),
         {:ok, total_volume} <-
           Sanbase.SocialData.social_volume(%{text: "*"}, from, to, interval, source) do
      # If `text_volume` is empty replace it with 0 mentions, so the end result
      # will be with all dominance = 0
      text_volume_map =
        text_volume |> Enum.into(%{}, fn elem -> {elem.datetime, elem.mentions_count} end)

      result =
        Enum.map(total_volume, fn %{datetime: datetime, mentions_count: total_mentions} ->
          text_mentions = Map.get(text_volume_map, datetime, 0)
          dominance = Sanbase.Math.percent_of(text_mentions, total_mentions) || 0.0

          %{
            datetime: datetime,
            dominance: dominance |> Sanbase.Math.round_float()
          }
        end)
        |> Enum.sort_by(&DateTime.to_unix(&1.datetime))

      {:ok, result}
    end
  end

  def social_dominance(%{slug: slug}, from, to, interval, source) do
    social_dominance_request(slug, from, to, interval, source |> to_string())
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Jason.decode(body)

        parse_result(result)

      {:ok, %HTTPoison.Response{status_code: status}} ->
        warn_result("Error status #{status} fetching social dominance for project #{slug}")

      {:error, %HTTPoison.Error{} = error} ->
        error_result(
          "Cannot fetch social dominance data for project #{slug}: #{
            HTTPoison.Error.message(error)
          }"
        )
    end
  end

  defp social_dominance_request(slug, from, to, interval, source) do
    cache_key =
      {:social_dominance_api_request, round_datetime(from), round_datetime(to), interval, source}
      |> Sanbase.Cache.hash()

    url = "#{metrics_hub_url()}/social_dominance?top_projects_size=10"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"slug", slug},
        {"from_timestamp", from |> DateTime.to_iso8601()},
        {"to_timestamp", to |> DateTime.to_iso8601()},
        {"interval", interval},
        {"source", source}
      ]
    ]

    Cache.get_or_store(cache_key, fn -> HTTPoison.get(url, [], options) end)
  end

  defp parse_result(%{"data" => map}) do
    map =
      Enum.map(map, fn {datetime, value} ->
        %{
          datetime: Sanbase.DateTimeUtils.from_iso8601!(datetime),
          dominance: (value * 100) |> Float.round(2)
        }
      end)
      |> Enum.sort_by(& &1.datetime, {:asc, DateTime})

    {:ok, map}
  end

  defp total_mentions(datapoint) do
    datapoint
    |> Enum.reject(fn {key, _} -> key == "datetime" end)
    |> Enum.map(fn {_, value} -> value end)
    |> Enum.sum()
    |> max(1.0)
  end

  defp tech_indicators_url() do
    Config.module_get(Sanbase.TechIndicators, :url)
  end

  defp metrics_hub_url() do
    Config.module_get(Sanbase.SocialData, :metricshub_url)
  end
end
