defmodule SanbaseWeb.Graphql.MostTweetsSocialDataTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn}
  end

  test "successfully fetch tweets", context do
    body = metricshub_data() |> Jason.encode!()
    resp = %HTTPoison.Response{status_code: 200, body: body}

    Sanbase.Mock.prepare_mock2(&HTTPoison.get/3, {:ok, resp})
    |> Sanbase.Mock.run_with_mocks(fn ->
      # Get the top 2 most positive tweets per slug in the given time range
      query = """
      {
        getMostTweets(
          tweetType: MOST_POSITIVE
          selector: { slugs: ["bitcoin", "ethereum"] }
          from: "2024-11-25T00:00:00Z"
          to: "2024-11-28T00:00:00Z"
          size: 2){
            slug
            tweets{
              datetime
              text
              screenName
              sentimentPositive
              sentimentNegative
              repliesCount
              retweetsCount
            }
          }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query))
        |> json_response(200)
        |> get_in(["data", "getMostTweets"])

      assert %{
               "slug" => "bitcoin",
               "tweets" => [
                 %{
                   "datetime" => "2024-11-26T18:21:30Z",
                   "repliesCount" => 0,
                   "retweetsCount" => 0,
                   "screenName" => "take_gains",
                   "sentimentNegative" => 0.0171372827,
                   "sentimentPositive" => 0.9828627173,
                   "text" =>
                     "Whipsaw wick completed, lets continue. \n\n$BTC https://t.co/e8mH8RUKjO"
                 },
                 %{
                   "datetime" => "2024-11-26T19:07:51Z",
                   "repliesCount" => 0,
                   "retweetsCount" => 0,
                   "screenName" => "IIICapital",
                   "sentimentNegative" => 0.0222001588,
                   "sentimentPositive" => 0.9777998412,
                   "text" =>
                     "Incredible podcast with two of the sharpest minds in bitcoin.\n\nThank you both for the time @Excellion and @dhruvbansal.\n\nTune in and comment whether you think bitcoin was an invention or discovery!"
                 }
               ]
             } in result

      assert %{
               "slug" => "ethereum",
               "tweets" => [
                 %{
                   "datetime" => "2024-11-26T17:07:36Z",
                   "repliesCount" => 0,
                   "retweetsCount" => 0,
                   "screenName" => "koeppelmann",
                   "sentimentNegative" => 0.0269591219,
                   "sentimentPositive" => 0.9730408781,
                   "text" =>
                     "Thanks for hosting this debate @laurashin! While I think Justin and I share a similar vision of what Ethereum should ideally become in a couple of years, he thinks we are on track for it - I believe decisive action is needed now to achieve that vision."
                 },
                 %{
                   "datetime" => "2024-11-27T14:00:12Z",
                   "repliesCount" => 0,
                   "retweetsCount" => 1,
                   "screenName" => "AerodromeFi",
                   "sentimentNegative" => 0.0277438289,
                   "sentimentPositive" => 0.9722561711,
                   "text" =>
                     "New Launch Alert ✈️\n\nA big welcome to @doge_eth_gov who have launched an $DOGE - $WETH pool on Aerodrome.\n\nBridge $DOGE from Ethereum mainnet to @base, powered by @axelar: https://t.co/wejMHuq62H\n\nLiquidity has been added and LP rewards incoming. https://t.co/A5lpoDZakD"
                 }
               ]
             } in result
    end)
  end

  defp metricshub_data() do
    %{
      "data" => %{
        "bitcoin" =>
          "[{\"screen_name\":\"take_gains\",\"text\":\"Whipsaw wick completed, lets continue. \\n\\n$BTC https:\\/\\/t.co\\/e8mH8RUKjO\",\"reply\":0,\"retweet\":0,\"timestamp\":\"2024-11-26T18:21:30\",\"sentiment_neg\":0.0171372827,\"sentiment_pos\":0.9828627173},{\"screen_name\":\"IIICapital\",\"text\":\"Incredible podcast with two of the sharpest minds in bitcoin.\\n\\nThank you both for the time @Excellion and @dhruvbansal.\\n\\nTune in and comment whether you think bitcoin was an invention or discovery!\",\"reply\":0,\"retweet\":0,\"timestamp\":\"2024-11-26T19:07:51\",\"sentiment_neg\":0.0222001588,\"sentiment_pos\":0.9777998412}]",
        "ethereum" =>
          "[{\"screen_name\":\"koeppelmann\",\"text\":\"Thanks for hosting this debate @laurashin! While I think Justin and I share a similar vision of what Ethereum should ideally become in a couple of years, he thinks we are on track for it - I believe decisive action is needed now to achieve that vision.\",\"reply\":0,\"retweet\":0,\"timestamp\":\"2024-11-26T17:07:36\",\"sentiment_neg\":0.0269591219,\"sentiment_pos\":0.9730408781},{\"screen_name\":\"AerodromeFi\",\"text\":\"New Launch Alert \\u2708\\ufe0f\\n\\nA big welcome to @doge_eth_gov who have launched an $DOGE - $WETH pool on Aerodrome.\\n\\nBridge $DOGE from Ethereum mainnet to @base, powered by @axelar: https:\\/\\/t.co\\/wejMHuq62H\\n\\nLiquidity has been added and LP rewards incoming. https:\\/\\/t.co\\/A5lpoDZakD\",\"reply\":0,\"retweet\":1,\"timestamp\":\"2024-11-27T14:00:12\",\"sentiment_neg\":0.0277438289,\"sentiment_pos\":0.9722561711}]"
      }
    }
  end
end
