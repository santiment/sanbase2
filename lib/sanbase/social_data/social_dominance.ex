defmodule Sanbase.SocialData.SocialDominance do
  import Sanbase.Utils.ErrorHandling
  import Sanbase.DateTimeUtils, only: [round_datetime: 1]

  alias Sanbase.Model.Project
  alias Sanbase.Cache

  require Mockery.Macro

  require Sanbase.Utils.Config, as: Config
  require SanbaseWeb.Graphql.Schema

  @recv_timeout 15_000
  @sources [:telegram, :professional_traders_chat, :reddit, :discord]

  def social_dominance(%{slug: slug}, from, to, interval, source)
      when source in [:all, "all", :total, "total"] do
    ticker = Project.ticker_by_slug(slug)
    ticker_slug = "#{ticker}_#{slug}"

    result =
      @sources
      |> Sanbase.Parallel.flat_map(
        fn source ->
          case social_dominance_request(from, to, interval, source |> to_string()) do
            {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
              {:ok, result} = Jason.decode(body)

              Enum.map(result, fn map ->
                {timestamp, rest} = Map.pop(map, "datetime")
                {DateTime.from_unix!(timestamp), rest}
              end)

            _ ->
              []
          end
        end,
        max_concurrency: 4
      )
      |> Enum.group_by(fn {datetime, _} -> datetime end, fn {_, data} -> data end)
      |> Enum.map(fn {datetime, maps_list} ->
        map =
          Enum.reduce(maps_list, %{}, fn map, acc ->
            Map.merge(map, acc, fn _k, v1, v2 -> v1 + v2 end)
          end)

        project_mentions = Map.get(map, ticker_slug, 0)
        total_mentions = Enum.reduce(map, 0, fn {_k, v}, acc -> acc + v end)

        dominance = Sanbase.Math.percent_of(project_mentions, total_mentions) || 0.0

        %{
          datetime: datetime,
          dominance: dominance |> Sanbase.Math.round_float()
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
    ticker = Project.ticker_by_slug(slug)
    ticker_slug = "#{ticker}_#{slug}"

    social_dominance_request(from, to, interval, source |> to_string())
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Jason.decode(body)

        parse_result(result, ticker_slug)

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

  defp source_to_indicator(<<"reddit", _::binary>>), do: "social_dominance_reddit"
  defp source_to_indicator(<<"telegram", _::binary>>), do: "social_dominance_telegram"
  defp source_to_indicator(<<"discord", _::binary>>), do: "social_dominance_discord"

  defp source_to_indicator(<<"professional_traders_chat", _::binary>>),
    do: "social_dominance_professional_traders_chat"

  defp social_dominance_request(from, to, interval, source) do
    cache_key =
      {:social_dominance_api_request, round_datetime(from), round_datetime(to), interval, source}
      |> Sanbase.Cache.hash()

    url = "#{tech_indicators_url()}/indicator/#{source_to_indicator(source)}"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"from_timestamp", DateTime.to_unix(from)},
        {"to_timestamp", DateTime.to_unix(to)},
        {"interval", interval}
      ]
    ]

    Cache.get_or_store(cache_key, fn -> HTTPoison.get(url, [], options) end)
  end

  defp parse_result(result, ticker_slug) do
    result =
      result
      |> Enum.map(fn
        %{"datetime" => datetime} = datapoint ->
          mentions = Map.get(datapoint, ticker_slug, 0)
          dominance = Sanbase.Math.percent_of(mentions, total_mentions(datapoint)) || 0.0

          %{
            datetime: DateTime.from_unix!(datetime),
            dominance: dominance |> Sanbase.Math.round_float()
          }
      end)
      |> Enum.sort_by(&DateTime.to_unix(&1.datetime))

    {:ok, result}
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
end
