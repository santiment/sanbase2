defmodule Sanbase.SocialData.News do
  import Sanbase.Utils.ErrorHandling

  alias Sanbase.Model.Project
  alias SanbaseWeb.Graphql.Cache

  require Mockery.Macro
  defp http_client, do: Mockery.Macro.mockable(HTTPoison)

  require Sanbase.Utils.Config, as: Config

  @recv_timeout 15_000

  def google_news(
        tag,
        datetime_from,
        datetime_to,
        size
      ) do
    google_news_request(
      tag,
      datetime_from,
      datetime_to,
      size
    )
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Jason.decode(body)
        IO.inspect(result)

      # parse_result(result, ticker_slug)

      {:ok, %HTTPoison.Response{status_code: status}} ->
        warn_result("Error status #{status} fetching news for tag #{tag}")

      {:error, %HTTPoison.Error{} = error} ->
        error_result("Cannot fetch news data for tag #{tag}: #{HTTPoison.Error.message(error)}")
    end
  end

  defp google_news_request(
         tag,
         datetime_from,
         datetime_to,
         size
       ) do
    # cache_key =
    #   Cache.cache_key(:google_news_api_request, %{
    #     tag: tag,
    #     from: datetime_from,
    #     to: datetime_to,
    #     size: size
    #   })

    # Cache.get_or_store(cache_key, fn ->
    from_unix = DateTime.to_unix(datetime_from)
    to_unix = DateTime.to_unix(datetime_to)

    url = "#{tech_indicators_url()}/indicator/google_news_feed"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"tag", tag},
        {"from_timestamp", from_unix},
        {"to_timestamp", to_unix},
        {"size", size}
      ]
    ]

    http_client().get(url, [], options)
    # end)
  end

  defp parse_result(result, ticker_slug) do
    result =
      result
      |> Enum.map(fn %{
                       "timestamp" => datetime,
                       "title" => title,
                       "description" => description,
                       "url" => url,
                       "source_name" => source_name
                     } = datapoint ->
        %{
          datetime: DateTime.from_unix!(datetime),
          title: title,
          description: description,
          url: url,
          source_name: source_name
        }
      end)

    {:ok, result}
  end

  defp tech_indicators_url() do
    Config.module_get(Sanbase.TechIndicators, :url)
  end
end
