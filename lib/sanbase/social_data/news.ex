defmodule Sanbase.SocialData.News do
  import Sanbase.Utils.ErrorHandling

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
        parse_result(result)

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
  end

  defp parse_result(result) do
    result =
      result
      |> Enum.sort(&(&1["timestamp"] <= &2["timestamp"]))
      |> Enum.map(fn %{
                       "timestamp" => dt,
                       "title" => title,
                       "description" => description,
                       "url" => url,
                       "source_name" => source_name,
                       "media_url" => media_url
                     } ->
        media_url = if media_url == "", do: nil, else: media_url

        %{
          datetime: Sanbase.DateTimeUtils.from_iso8601!(dt),
          title: title,
          description: description,
          url: url,
          source_name: source_name,
          media_url: media_url
        }
      end)

    {:ok, result}
  end

  defp tech_indicators_url() do
    Config.module_get(Sanbase.TechIndicators, :url)
  end
end
