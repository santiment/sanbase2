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
    body = Jason.encode!(metricshub_data())
    resp = %HTTPoison.Response{status_code: 200, body: body}

    (&HTTPoison.get/3)
    |> Sanbase.Mock.prepare_mock2({:ok, resp})
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
              tweetId
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
                   "datetime" => "2024-11-27T21:19:50Z",
                   "repliesCount" => 0,
                   "retweetsCount" => 0,
                   "screenName" => "CryptoLifer33",
                   "sentimentNegative" => 0.0044069796,
                   "sentimentPositive" => 0.9955930204,
                   "text" =>
                     "Life is good. I made thousands trading today and life is good. Thank God, thanks to Bitcoin, my family and #Florida What do you do to celebrate your wins? https://t.co/gY5c5Eb8Dh",
                   "tweetId" => "1861882647930085536"
                 },
                 %{
                   "datetime" => "2024-11-26T18:21:30Z",
                   "repliesCount" => 0,
                   "retweetsCount" => 0,
                   "screenName" => "take_gains",
                   "sentimentNegative" => 0.0171372827,
                   "sentimentPositive" => 0.9828627173,
                   "text" => "Whipsaw wick completed, lets continue. \n\n$BTC https://t.co/e8mH8RUKjO",
                   "tweetId" => "1861475381548851381"
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
                     "Thanks for hosting this debate @laurashin! While I think Justin and I share a similar vision of what Ethereum should ideally become in a couple of years, he thinks we are on track for it - I believe decisive action is needed now to achieve that vision.",
                   "tweetId" => "1861456784457654773"
                 },
                 %{
                   "datetime" => "2024-11-27T14:00:12Z",
                   "repliesCount" => 0,
                   "retweetsCount" => 1,
                   "screenName" => "AerodromeFi",
                   "sentimentNegative" => 0.0277438289,
                   "sentimentPositive" => 0.9722561711,
                   "text" =>
                     "New Launch Alert ✈️\n\nA big welcome to @doge_eth_gov who have launched an $DOGE - $WETH pool on Aerodrome.\n\nBridge $DOGE from Ethereum mainnet to @base, powered by @axelar: https://t.co/wejMHuq62H\n\nLiquidity has been added and LP rewards incoming. https://t.co/A5lpoDZakD",
                   "tweetId" => "1861772012814991729"
                 }
               ]
             } in result
    end)
  end

  defp metricshub_data do
    %{
      "data" => %{
        "bitcoin" =>
          ~s([{"tweet_id":1861882647930085536,"screen_name":"CryptoLifer33","text":"Life is good. I made thousands trading today and life is good. Thank God, thanks to Bitcoin, my family and #Florida What do you do to celebrate your wins? https:\\/\\/t.co\\/gY5c5Eb8Dh","reply":0,"retweet":0,"timestamp":"2024-11-27T21:19:50","sentiment_neg":0.0044069796,"sentiment_pos":0.9955930204},{"tweet_id":1861475381548851381,"screen_name":"take_gains","text":"Whipsaw wick completed, lets continue. \\n\\n$BTC https:\\/\\/t.co\\/e8mH8RUKjO","reply":0,"retweet":0,"timestamp":"2024-11-26T18:21:30","sentiment_neg":0.0171372827,"sentiment_pos":0.9828627173}]),
        "ethereum" =>
          ~s([{"tweet_id":1861456784457654773,"screen_name":"koeppelmann","text":"Thanks for hosting this debate @laurashin! While I think Justin and I share a similar vision of what Ethereum should ideally become in a couple of years, he thinks we are on track for it - I believe decisive action is needed now to achieve that vision.","reply":0,"retweet":0,"timestamp":"2024-11-26T17:07:36","sentiment_neg":0.0269591219,"sentiment_pos":0.9730408781},{"tweet_id":1861772012814991729,"screen_name":"AerodromeFi","text":"New Launch Alert \\u2708\\ufe0f\\n\\nA big welcome to @doge_eth_gov who have launched an $DOGE - $WETH pool on Aerodrome.\\n\\nBridge $DOGE from Ethereum mainnet to @base, powered by @axelar: https:\\/\\/t.co\\/wejMHuq62H\\n\\nLiquidity has been added and LP rewards incoming. https:\\/\\/t.co\\/A5lpoDZakD","reply":0,"retweet":1,"timestamp":"2024-11-27T14:00:12","sentiment_neg":0.0277438289,"sentiment_pos":0.9722561711}])
      }
    }
  end
end
