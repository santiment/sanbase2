defmodule Sanbase.SocialData.SocialDominance do
  import Sanbase.Utils.ErrorHandling

  alias Sanbase.Model.Project
  alias SanbaseWeb.Graphql.Cache

  require Mockery.Macro
  defp http_client, do: Mockery.Macro.mockable(HTTPoison)

  require Sanbase.Utils.Config, as: Config

  @recv_timeout 15_000

  @sources Absinthe.Schema.lookup_type(SanbaseWeb.Graphql.Schema, :social_dominance_sources).values
           |> Map.keys()
           |> List.delete(:all)

  def social_dominance(
        slug,
        datetime_from,
        datetime_to,
        interval,
        :all
      ) do
    result =
      @sources
      |> Sanbase.Parallel.map(
        fn source ->
          {:ok, result} = social_dominance(slug, datetime_from, datetime_to, interval, source)

          result
        end,
        max_concurrency: 10
      )
      |> List.zip()
      |> Enum.map(&Tuple.to_list/1)
      |> Enum.map(fn all_sources_point ->
        average_dominance =
          all_sources_point
          |> Enum.map(fn point -> point.dominance end)
          |> Enum.sum()
          |> Kernel./(length(@sources))

        %{
          datetime: all_sources_point |> List.first() |> Map.get(:datetime),
          dominance: average_dominance
        }
      end)

    {:ok, result}
  end

  def social_dominance(
        slug,
        datetime_from,
        datetime_to,
        interval,
        source
      ) do
    ticker = Project.ticker_by_slug(slug)
    ticker_slug = "#{ticker}_#{slug}"

    social_dominance_request(
      datetime_from,
      datetime_to,
      interval,
      source
    )
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

  defp social_dominance_request(
         datetime_from,
         datetime_to,
         interval,
         source
       ) do
    cache_key =
      Cache.cache_key(:social_dominance_api_request, %{
        from: datetime_from,
        to: datetime_to,
        interval: interval,
        source: source
      })

    Cache.get_or_store(cache_key, fn ->
      from_unix = DateTime.to_unix(datetime_from)
      to_unix = DateTime.to_unix(datetime_to)

      url = "#{tech_indicators_url()}/indicator/social_dominance_#{source}"

      options = [
        recv_timeout: @recv_timeout,
        params: [
          {"from_timestamp", from_unix},
          {"to_timestamp", to_unix},
          {"interval", interval}
        ]
      ]

      http_client().get(url, [], options)
    end)
  end

  defp parse_result(result, ticker_slug) do
    result =
      result
      |> Enum.map(fn %{
                       "datetime" => datetime
                     } = datapoint ->
        %{
          datetime: DateTime.from_unix!(datetime),
          dominance: Map.get(datapoint, ticker_slug, 0) * 100 / total_mentions(datapoint)
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
