defmodule SanbaseWeb.Graphql.DynamicWatchlistTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user = insert(:user)

    infr_eth = insert(:infrastructure, %{code: "ETH"})

    stablecoin = insert(:market_segment, %{name: "stablecoin"})
    coin = insert(:market_segment, %{name: "coin"})
    mineable = insert(:market_segment, %{name: "mineable"})

    insert(:project, %{ticker: "TUSD", slug: "tether", market_segment: stablecoin})
    insert(:latest_cmc_data, %{coinmarketcap_id: "tether", rank: 4, volume_usd: 3_000_000_000})

    insert(:project, %{
      ticker: "DAI",
      slug: "dai",
      market_segment: stablecoin,
      infrastructure: infr_eth,
      main_contract_address: "0x" <> Sanbase.TestUtils.random_string()
    })

    insert(:latest_cmc_data, %{coinmarketcap_id: "dai", rank: 40, volume_usd: 15_000_000})

    insert(:project, %{ticker: "ETH", slug: "ethereum", market_segment: mineable})
    insert(:latest_cmc_data, %{coinmarketcap_id: "ethereum", rank: 2, volume_usd: 3_000_000_000})

    insert(:project, %{ticker: "BTC", slug: "bitcoin", market_segment: mineable})
    insert(:latest_cmc_data, %{coinmarketcap_id: "bitcoin", rank: 1, volume_usd: 15_000_000_000})

    insert(:project, %{ticker: "XRP", slug: "ripple", market_segment: mineable})
    insert(:latest_cmc_data, %{coinmarketcap_id: "ripple", rank: 3, volume_usd: 1_000_000_000})

    insert(:project, %{
      ticker: "MKR",
      slug: "maker",
      market_segment: coin,
      infrastructure: infr_eth,
      main_contract_address: "0x" <> Sanbase.TestUtils.random_string()
    })

    insert(:latest_cmc_data, %{coinmarketcap_id: "maker", rank: 20, volume_usd: 150_000_000})

    insert(:project, %{
      ticker: "SAN",
      slug: "santiment",
      market_segment: coin,
      infrastructure: infr_eth,
      main_contract_address: "0x" <> Sanbase.TestUtils.random_string()
    })

    insert(:latest_cmc_data, %{coinmarketcap_id: "santiment", rank: 95, volume_usd: 100_000})

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  test "dynamic watchlist for selector", %{conn: conn, user: user} do
    function = %{
      "name" => "selector",
      "args" => %{
        "filters" => [
          %{
            "metric" => "daily_active_addresses",
            "from" => "#{Timex.shift(Timex.now(), days: -7)}",
            "to" => "#{Timex.now()}",
            "aggregation" => "#{:last}",
            "operator" => "#{:greater_than_or_equal_to}",
            "threshold" => 10
          }
        ]
      }
    }

    Sanbase.Mock.prepare_mock2(
      &Sanbase.Metric.slugs_by_filter/6,
      {:ok, ["ethereum", "dai", "bitcoin"]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result = execute_mutation(conn, query(function))
      user_list = result["data"]["createWatchlist"]

      assert user_list["name"] == "My list"
      assert user_list["color"] == "BLACK"
      assert user_list["isPublic"] == false
      assert user_list["user"]["id"] == user.id |> to_string()

      assert %{"project" => %{"slug" => "dai"}} in user_list["listItems"]
      assert %{"project" => %{"slug" => "bitcoin"}} in user_list["listItems"]
      assert %{"project" => %{"slug" => "ethereum"}} in user_list["listItems"]
    end)
  end

  test "dynamic watchlist for market segments", %{conn: conn, user: user} do
    function = %{"name" => "market_segment", "args" => %{"market_segment" => "stablecoin"}}

    result = execute_mutation(conn, query(function))
    user_list = result["data"]["createWatchlist"]

    assert user_list["name"] == "My list"
    assert user_list["color"] == "BLACK"
    assert user_list["isPublic"] == false
    assert user_list["user"]["id"] == user.id |> to_string()

    assert %{"project" => %{"slug" => "dai"}} in user_list["listItems"]
    assert %{"project" => %{"slug" => "tether"}} in user_list["listItems"]
  end

  test "dynamic watchlist for top erc20 projects", %{conn: conn} do
    function = %{"name" => "top_erc20_projects", "args" => %{"size" => 2}}
    result = execute_mutation(conn, query(function))
    user_list = result["data"]["createWatchlist"]

    assert user_list["listItems"] == [
             %{"project" => %{"slug" => "maker"}},
             %{"project" => %{"slug" => "dai"}}
           ]
  end

  test "dynamic watchlist for top erc20 projects ignoring some projects", %{conn: conn} do
    function = %{
      "name" => "top_erc20_projects",
      "args" => %{"size" => 2, "ignored_projects" => ["dai"]}
    }

    result = execute_mutation(conn, query(function))
    user_list = result["data"]["createWatchlist"]

    assert user_list["listItems"] == [
             %{"project" => %{"slug" => "maker"}},
             %{"project" => %{"slug" => "santiment"}}
           ]
  end

  test "dynamic watchlist for top all projects", %{conn: conn} do
    function = %{"name" => "top_all_projects", "args" => %{"size" => 3}}
    result = execute_mutation(conn, query(function))
    user_list = result["data"]["createWatchlist"]

    assert user_list["listItems"] == [
             %{"project" => %{"slug" => "bitcoin"}},
             %{"project" => %{"slug" => "ethereum"}},
             %{"project" => %{"slug" => "ripple"}}
           ]
  end

  test "dynamic watchlist for min volume", %{conn: conn} do
    function = %{"name" => "min_volume", "args" => %{"min_volume" => 1_000_000_000}}
    result = execute_mutation(conn, query(function))
    user_list = result["data"]["createWatchlist"]

    assert user_list["listItems"] == [
             %{"project" => %{"slug" => "bitcoin"}},
             %{"project" => %{"slug" => "ethereum"}},
             %{"project" => %{"slug" => "ripple"}},
             %{"project" => %{"slug" => "tether"}}
           ]
  end

  test "dynamic watchlist for slug list", %{conn: conn} do
    function = %{"name" => "slugs", "args" => %{"slugs" => ["bitcoin", "santiment"]}}
    result = execute_mutation(conn, query(function))
    user_list = result["data"]["createWatchlist"]

    assert user_list["listItems"] == [
             %{"project" => %{"slug" => "bitcoin"}},
             %{"project" => %{"slug" => "santiment"}}
           ]
  end

  test "dynamic watchlist for currently trending projects", %{conn: conn} do
    with_mock(Sanbase.SocialData.TrendingWords,
      get_currently_trending_words: fn ->
        {:ok,
         [
           %{word: "SAN", score: 5},
           %{word: "bitcoin", score: 3},
           %{word: "Ripple", score: 2},
           %{word: "random_str", score: 1}
         ]}
      end
    ) do
      function = %{"name" => "trending_projects"}
      result = execute_mutation(conn, query(function))
      user_list = result["data"]["createWatchlist"]
      slugs = user_list["listItems"] |> Enum.map(fn %{"project" => %{"slug" => slug}} -> slug end)

      assert slugs |> Enum.sort() == ["santiment", "bitcoin", "ripple"] |> Enum.sort()
    end
  end

  defp query(function, opts \\ []) when is_map(function) do
    name = Keyword.get(opts, :name, "My list")
    color = Keyword.get(opts, :color, "BLACK")
    function = function |> Jason.encode!()

    ~s|
    mutation {
      createWatchlist(
        name: '#{name}'
        color: #{color}
        function: '#{function}'
        ) {
         id
         name
         color
         isPublic
         user{ id }

         listItems{
           project{ slug }
         }
      }
    }
    |
    |> String.replace(~r|\"|, ~S|\\"|)
    |> String.replace(~r|'|, ~S|"|)
  end

  defp execute_mutation(conn, query) do
    conn
    |> post("/graphql", mutation_skeleton(query))
    |> json_response(200)
  end
end
