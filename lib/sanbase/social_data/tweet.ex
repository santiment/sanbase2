defmodule Sanbase.SocialData.Tweet do
  require Mockery.Macro
  @tweet_types [:most_positive, :most_negative, :most_retweets, :most_replies]
  @tweet_type_mapping %{
    most_positive: :sentiment_pos,
    most_negative: :sentiment_neg,
    most_retweets: :retweet,
    most_replies: :reply
  }
  @recv_timeout 25_000
  def get_most_tweets(%{} = selector, type, from, to, size) do
    slugs = (Map.get(selector, :slug) || Map.get(selector, :slugs)) |> List.wrap()

    tweets_request(slugs, type, from, to, size)
    |> handle_tweets_response()
  end

  defp handle_tweets_response({:ok, %HTTPoison.Response{status_code: 200, body: json_body}}) do
    case Jason.decode(json_body) do
      {:ok, %{"data" => data}} ->
        {:ok, decode_tweets_data(data)}

      _ ->
        {:error, "Malformed response fetching tweets"}
    end
  end

  defp handle_tweets_response({:ok, %HTTPoison.Response{status_code: status}}) do
    {:error, "Error status #{status} fetching tweets"}
  end

  defp decode_tweets_data(data_map) when is_map(data_map) do
    data_map
    |> Enum.map(fn {slug, json_list} ->
      list = Jason.decode!(json_list)

      tweets =
        Enum.map(list, fn map ->
          %{
            tweet_id: Map.fetch!(map, "tweet_id") |> to_string(),
            text: Map.fetch!(map, "text"),
            screen_name: Map.fetch!(map, "screen_name"),
            datetime:
              Map.fetch!(map, "timestamp")
              |> NaiveDateTime.from_iso8601!()
              |> DateTime.from_naive!("Etc/UTC"),
            replies_count: Map.fetch!(map, "reply"),
            sentiment_positive: Map.fetch!(map, "sentiment_pos"),
            sentiment_negative: Map.fetch!(map, "sentiment_neg"),
            retweets_count: Map.fetch!(map, "retweet")
          }
        end)

      %{slug: slug, tweets: tweets}
    end)
  end

  defp tweets_request(slugs, type, from, to, size)
       when type in @tweet_types and is_list(slugs) do
    url = Path.join([metrics_hub_url(), "fetch_documents"])

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"slugs", slugs |> List.wrap() |> Enum.join(",")},
        {"from_timestamp", from |> DateTime.truncate(:second) |> DateTime.to_iso8601()},
        {"to_timestamp", to |> DateTime.truncate(:second) |> DateTime.to_iso8601()},
        {"size", size},
        {"source", "twitter"},
        {"most_type", Map.fetch!(@tweet_type_mapping, type)}
      ]
    ]

    http_client().get(url, [], options)
  end

  defp http_client, do: Mockery.Macro.mockable(HTTPoison)

  defp metrics_hub_url() do
    Sanbase.Utils.Config.module_get(Sanbase.SocialData, :metricshub_url)
  end
end
