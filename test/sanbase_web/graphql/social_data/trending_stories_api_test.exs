defmodule SanbaseWeb.Graphql.TrendingStoriesApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.SocialData

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))

    conn = setup_jwt_auth(build_conn(), user)

    [
      conn: conn,
      dt1: ~U[2019-01-01 00:00:00Z],
      dt2: ~U[2019-01-02 00:00:00Z],
      dt3: ~U[2019-01-03 00:00:00Z]
    ]
  end

  describe "get trending words api" do
    test "Sanbase PRO user sees all stories", context do
      %{dt1: dt1, dt3: dt3} = context

      rows = trending_stories_rows(context)

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        args = %{from: dt1, to: dt3, interval: "1d", size: 2}

        query = trending_stories_query(args)
        result = execute(context.conn, query)

        assert result == %{
                 "data" => %{
                   "getTrendingStories" => [
                     %{
                       "datetime" => "2019-01-01T00:00:00Z",
                       "topStories" => [
                         %{
                           "bearishRatio" => 0.27668887,
                           "relatedTokens" => [],
                           "score" => 757.0655,
                           "searchText" => "(web3 OR orbit OR thanks OR tech OR omni)",
                           "summary" =>
                             "The word 'web3' is trending due to extensive discussions about its role in bridging traditional Web2 systems with decentralized blockchain technologies",
                           "title" => "Web3 Tech Orbit"
                         },
                         %{
                           "bearishRatio" => 0.2850633,
                           "relatedTokens" => ["USDT_tether", "BTC_bitcoin"],
                           "score" => 575.01733,
                           "searchText" => "(tether OR btc)",
                           "summary" =>
                             "The word 'btc' is trending due to multiple mentions related to Bitcoin in various contexts including trading activity, strategic reserve bills, institutional purchases",
                           "title" => "BTC Tether Trends"
                         },
                         %{
                           "bearishRatio" => 0.28465262,
                           "relatedTokens" => [
                             "ETH_ethereum",
                             "USDT_tether",
                             "BTC_bitcoin",
                             "SOL_solana",
                             "XRP_xrp",
                             "HOT_holo",
                             "PEPE_pepe",
                             "BNB_binance-coin"
                           ],
                           "score" => 443.36606,
                           "searchText" =>
                             "(bills OR florida OR bnb OR bitcoin OR million OR reserve OR new)",
                           "summary" =>
                             "The word 'new' is trending because it appears frequently in announcements and news about recent developments in the crypto and finance sectors",
                           "title" => "New Bitcoin Bills"
                         },
                         %{
                           "bearishRatio" => 0.31934676,
                           "relatedTokens" => ["LINK_chainlink"],
                           "score" => 373.1052,
                           "searchText" =>
                             "(kernel OR link OR trade OR support OR pizza OR help OR trading OR htx)",
                           "summary" =>
                             "The word 'pizza' is trending due to a community event called #PizzaDay organized by the HTX crypto exchange",
                           "title" => "Pizza Trading Event"
                         }
                       ]
                     }
                   ]
                 }
               }
      end)
    end

    test "Free user see masked first 3 stories" do
      System.put_env("MASK_FIRST_3_WORDS_FREE_USER", "true")
      now = DateTime.utc_now(:second)
      from = DateTime.add(now, -2, :day)
      context = %{dt1: from, dt3: now}

      rows = trending_stories_rows(context)

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        args = %{from: from, to: now, interval: "1d", size: 2}

        query = trending_stories_query(args)
        result = execute(build_conn(), query)

        assert result == %{
                 "data" => %{
                   "getTrendingStories" => [
                     %{
                       "datetime" => DateTime.to_iso8601(from),
                       "topStories" => [
                         %{
                           "bearishRatio" => 0.27668887,
                           "relatedTokens" => ["***"],
                           "score" => 757.0655,
                           "searchText" => "***",
                           "summary" => "***",
                           "title" => "***"
                         },
                         %{
                           "bearishRatio" => 0.2850633,
                           "relatedTokens" => ["***"],
                           "score" => 575.01733,
                           "searchText" => "***",
                           "summary" => "***",
                           "title" => "***"
                         },
                         %{
                           "bearishRatio" => 0.28465262,
                           "relatedTokens" => ["***"],
                           "score" => 443.36606,
                           "searchText" => "***",
                           "summary" => "***",
                           "title" => "***"
                         },
                         %{
                           "bearishRatio" => 0.31934676,
                           "relatedTokens" => ["LINK_chainlink"],
                           "score" => 373.1052,
                           "searchText" =>
                             "(kernel OR link OR trade OR support OR pizza OR help OR trading OR htx)",
                           "summary" =>
                             "The word 'pizza' is trending due to a community event called #PizzaDay organized by the HTX crypto exchange",
                           "title" => "Pizza Trading Event"
                         }
                       ]
                     }
                   ]
                 }
               }
      end)
    end

    test "error", context do
      %{dt1: dt1, dt2: dt2} = context

      Sanbase.Mock.prepare_mock2(
        &SocialData.TrendingStories.get_trending_stories/5,
        {:error, "Something broke"}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        args = %{from: dt1, to: dt2, interval: "1h", size: 10}

        query = trending_stories_query(args)

        error_msg =
          execute(context.conn, query)
          |> get_error_message()

        assert error_msg =~ "Something broke"
      end)
    end
  end

  defp trending_stories_rows(context) do
    [
      [
        DateTime.to_unix(context.dt1),
        "Web3 Tech Orbit",
        "(web3 OR orbit OR thanks OR tech OR omni)",
        757.0655,
        [],
        "The word 'web3' is trending due to extensive discussions about its role in bridging traditional Web2 systems with decentralized blockchain technologies",
        0.39370275,
        0.27668887
      ],
      [
        DateTime.to_unix(context.dt1),
        "BTC Tether Trends",
        "(tether OR btc)",
        575.01733,
        ["USDT_tether", "BTC_bitcoin"],
        "The word 'btc' is trending due to multiple mentions related to Bitcoin in various contexts including trading activity, strategic reserve bills, institutional purchases",
        0.41820693,
        0.2850633
      ],
      [
        DateTime.to_unix(context.dt1),
        "New Bitcoin Bills",
        "(bills OR florida OR bnb OR bitcoin OR million OR reserve OR new)",
        443.36606,
        [
          "ETH_ethereum",
          "USDT_tether",
          "BTC_bitcoin",
          "SOL_solana",
          "XRP_xrp",
          "HOT_holo",
          "PEPE_pepe",
          "BNB_binance-coin"
        ],
        "The word 'new' is trending because it appears frequently in announcements and news about recent developments in the crypto and finance sectors",
        0.39526817,
        0.28465262
      ],
      [
        DateTime.to_unix(context.dt1),
        "Pizza Trading Event",
        "(kernel OR link OR trade OR support OR pizza OR help OR trading OR htx)",
        373.1052,
        ["LINK_chainlink"],
        "The word 'pizza' is trending due to a community event called #PizzaDay organized by the HTX crypto exchange",
        0.33390155,
        0.31934676
      ]
    ]
  end

  defp trending_stories_query(args) do
    """
    {
      getTrendingStories(#{map_to_args(args)}){
        datetime
        topStories{
          title
          summary
          relatedTokens
          bearishRatio
          bearishRatio
          score
          searchText
        }
      }
    }
    """
  end

  defp execute(conn, query) do
    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp get_error_message(result) do
    result
    |> Map.get("errors")
    |> hd()
    |> Map.get("message")
  end
end
