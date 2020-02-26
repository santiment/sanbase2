defmodule Sanbase.SocialData.SocialDominance do
  import Sanbase.Utils.ErrorHandling

  alias Sanbase.Model.Project
  alias SanbaseWeb.Graphql.Cache

  require Mockery.Macro
  defp http_client, do: Mockery.Macro.mockable(HTTPoison)

  require Sanbase.Utils.Config, as: Config
  require SanbaseWeb.Graphql.Schema

  @recv_timeout 15_000
  @sources [:telegram, :professional_traders_chat, :reddit, :discord]

  def social_dominance(slug, from, to, interval, source)
      when source in [:all, "all", :total, "total"] do
    result =
      @sources
      |> Sanbase.Parallel.map(
        fn source ->
          {:ok, result} = social_dominance(slug, from, to, interval, source)

          result
        end,
        max_concurrency: 4
      )
      |> List.zip()
      |> Enum.map(&Tuple.to_list/1)
      |> Enum.map(fn all_sources_point ->
        average_dominance =
          all_sources_point
          |> Enum.reduce(0, &(&2 + &1.dominance))
          |> Kernel./(length(@sources))

        %{
          datetime: all_sources_point |> List.first() |> Map.get(:datetime),
          dominance: average_dominance
        }
      end)

    {:ok, result}
  end

  def social_dominance(slug, from, to, interval, source) do
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
      Cache.cache_key(
        :social_dominance_api_request,
        %{from: from, to: to, interval: interval, source: source}
      )

    Cache.get_or_store(cache_key, fn ->
      url = "#{tech_indicators_url()}/indicator/#{source_to_indicator(source)}"

      options = [
        recv_timeout: @recv_timeout,
        params: [
          {"from_timestamp", DateTime.to_unix(from)},
          {"to_timestamp", DateTime.to_unix(to)},
          {"interval", interval}
        ]
      ]

      http_client().get(url, [], options)
    end)
  end

  defp parse_result(result, ticker_slug) do
    result =
      result
      |> Enum.map(fn
        %{"datetime" => datetime} = datapoint ->
          dominance = Map.get(datapoint, ticker_slug, 0) * 100 / total_mentions(datapoint)
          dominance = dominance |> Sanbase.Math.round_float()

          %{
            datetime: DateTime.from_unix!(datetime),
            dominance: dominance
          }
      end)

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
