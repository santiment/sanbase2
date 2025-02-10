defmodule SanbaseWeb.Graphql.ProjectDynamicWatchlistTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Clickhouse.MetricAdapter

  setup do
    user = insert(:user)

    infr_eth = insert(:infrastructure, %{code: "ETH"})

    stablecoin = insert(:market_segment, %{name: "stablecoin"})
    coin = insert(:market_segment, %{name: "coin"})
    mineable = insert(:market_segment, %{name: "mineable"})

    p1 = insert(:project, %{ticker: "TUSD", slug: "tether", market_segments: [stablecoin]})
    insert(:latest_cmc_data, %{coinmarketcap_id: "tether", rank: 4, volume_usd: 3_000_000_000})

    p2 =
      insert(:project, %{
        ticker: "DAI",
        slug: "dai",
        market_segments: [stablecoin],
        infrastructure: infr_eth
      })

    insert(:latest_cmc_data, %{coinmarketcap_id: "dai", rank: 40, volume_usd: 15_000_000})

    p3 = insert(:project, %{ticker: "ETH", slug: "ethereum", market_segments: [mineable]})
    insert(:latest_cmc_data, %{coinmarketcap_id: "ethereum", rank: 2, volume_usd: 3_000_000_000})

    p4 = insert(:project, %{ticker: "BTC", slug: "bitcoin", market_segments: [mineable]})
    insert(:latest_cmc_data, %{coinmarketcap_id: "bitcoin", rank: 1, volume_usd: 15_000_000_000})

    p5 = insert(:project, %{ticker: "XRP", slug: "xrp", market_segments: [mineable]})
    insert(:latest_cmc_data, %{coinmarketcap_id: "xrp", rank: 3, volume_usd: 1_000_000_000})

    p6 =
      insert(:project, %{
        ticker: "MKR",
        slug: "maker",
        market_segments: [coin],
        infrastructure: infr_eth
      })

    insert(:latest_cmc_data, %{coinmarketcap_id: "maker", rank: 20, volume_usd: 150_000_000})

    p7 =
      insert(:project, %{
        ticker: "SAN",
        slug: "santiment",
        market_segments: [coin],
        infrastructure: infr_eth
      })

    insert(:latest_cmc_data, %{coinmarketcap_id: "santiment", rank: 95, volume_usd: 100_000})

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user, p1: p1, p2: p2, p3: p3, p4: p4, p5: p5, p6: p6, p7: p7}
  end

  test "wrongly configured function fails on create", %{conn: conn} do
    function = %{
      "name" => "selector",
      "args" => %{
        # mistyped
        "filterss" => [
          %{
            "name" => "metric",
            "args" => %{
              "metric" => "daily_active_addresses",
              "from" => "#{Timex.shift(DateTime.utc_now(), days: -7)}",
              "to" => "#{DateTime.utc_now()}",
              "aggregation" => "#{:last}",
              "operator" => "#{:greater_than_or_equal_to}",
              "threshold" => 10
            }
          }
        ]
      }
    }

    error =
      conn
      |> do_execute_mutation(create_watchlist_query(function: function))
      |> Map.get("errors")
      |> hd()

    assert %{
             "details" => %{
               "function" => [
                 "Provided watchlist function is not valid. Reason: Dynamic watchlist 'selector' has unsupported fields: [\"filterss\"]"
               ]
             },
             "message" => "Cannot create user list"
           } = error
  end

  test "wrongly configured function fails on update", %{conn: conn, user: user} do
    watchlist = insert(:watchlist, user: user)

    function = %{
      "name" => "selector",
      "args" => %{
        # mistyped
        "filterss" => [
          %{
            "name" => "metric",
            "args" => %{
              "metric" => "daily_active_addresses",
              "from" => "#{Timex.shift(DateTime.utc_now(), days: -7)}",
              "to" => "#{DateTime.utc_now()}",
              "aggregation" => "#{:last}",
              "operator" => "#{:greater_than_or_equal_to}",
              "threshold" => 10
            }
          }
        ]
      }
    }

    error =
      conn
      |> do_execute_mutation(update_watchlist_query(id: watchlist.id, function: function))
      |> Map.get("errors")
      |> hd()

    assert %{
             "details" => %{
               "function" => [
                 "Provided watchlist function is not valid. Reason: Dynamic watchlist 'selector' has unsupported fields: [\"filterss\"]"
               ]
             },
             "message" => "Cannot update user list"
           } = error
  end

  test "dynamic watchlist for selector", %{conn: conn, user: user} do
    # Have at least 1 project that is not included in the result
    insert(:random_erc20_project)

    function = %{
      "name" => "selector",
      "args" => %{
        "filters" => [
          %{
            "name" => "metric",
            "args" => %{
              "metric" => "daily_active_addresses",
              "from" => "#{Timex.shift(DateTime.utc_now(), days: -7)}",
              "to" => "#{DateTime.utc_now()}",
              "aggregation" => "#{:last}",
              "operator" => "#{:greater_than_or_equal_to}",
              "threshold" => 10
            }
          }
        ]
      }
    }

    (&MetricAdapter.slugs_by_filter/6)
    |> Sanbase.Mock.prepare_mock2({:ok, ["ethereum", "dai", "bitcoin"]})
    |> Sanbase.Mock.run_with_mocks(fn ->
      user_list = execute_mutation(conn, create_watchlist_query(function: function))

      assert user_list["name"] == "My list"
      assert user_list["color"] == "BLACK"
      assert user_list["isPublic"] == false
      assert user_list["user"]["id"] == to_string(user.id)

      assert length(user_list["listItems"]) == 3
      assert %{"project" => %{"slug" => "dai"}} in user_list["listItems"]
      assert %{"project" => %{"slug" => "bitcoin"}} in user_list["listItems"]
      assert %{"project" => %{"slug" => "ethereum"}} in user_list["listItems"]
    end)
  end

  test "dynamic watchlist for selector with filtersCombinator OR", context do
    %{conn: conn, p1: p1, p2: p2, p3: p3, p4: p4, p5: p5} = context
    # Have at least 1 project that is not included in the result
    insert(:random_erc20_project)

    function = %{
      "name" => "selector",
      "args" => %{
        "filters_combinator" => :or,
        "filters" => [
          %{
            "name" => "metric",
            "args" => %{
              "metric" => "daily_active_addresses",
              "from" => "#{Timex.shift(DateTime.utc_now(), days: -7)}",
              "to" => "#{DateTime.utc_now()}",
              "aggregation" => "#{:last}",
              "operator" => "#{:greater_than_or_equal_to}",
              "threshold" => 100
            }
          },
          %{
            "name" => "metric",
            "args" => %{
              "metric" => "nvt",
              "from" => "#{Timex.shift(DateTime.utc_now(), days: -7)}",
              "to" => "#{DateTime.utc_now()}",
              "aggregation" => "#{:last}",
              "operator" => "#{:less_than}",
              "threshold" => 10
            }
          }
        ]
      }
    }

    MetricAdapter
    |> Sanbase.Mock.prepare_mock(:slugs_by_filter, fn
      "daily_active_addresses", _, _, _, _, _ -> {:ok, [p1.slug, p2.slug, p3.slug]}
      "nvt", _, _, _, _, _ -> {:ok, [p3.slug, p4.slug, p5.slug]}
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      result = do_execute_mutation(conn, create_watchlist_query(function: function))

      user_list = result["data"]["createWatchlist"]

      assert length(user_list["listItems"]) == 5
      assert %{"project" => %{"slug" => p1.slug}} in user_list["listItems"]
      assert %{"project" => %{"slug" => p2.slug}} in user_list["listItems"]
      assert %{"project" => %{"slug" => p3.slug}} in user_list["listItems"]
      assert %{"project" => %{"slug" => p4.slug}} in user_list["listItems"]
      assert %{"project" => %{"slug" => p5.slug}} in user_list["listItems"]
    end)
  end

  test "dynamic watchlist for selector - dynamic datetimes", %{conn: conn, user: user} do
    # Have at least 1 project that is not included in the result
    insert(:random_erc20_project)

    function = %{
      "name" => "selector",
      "args" => %{
        "filters" => [
          %{
            "name" => "metric",
            "args" => %{
              "metric" => "daily_active_addresses",
              "dynamicFrom" => "7d",
              "dynamicTo" => "now",
              "aggregation" => "#{:last}",
              "operator" => "#{:greater_than_or_equal_to}",
              "threshold" => 10
            }
          }
        ]
      }
    }

    (&MetricAdapter.slugs_by_filter/6)
    |> Sanbase.Mock.prepare_mock2({:ok, ["ethereum", "dai", "bitcoin"]})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        do_execute_mutation(conn, create_watchlist_query(function: function, is_screener: true))

      user_list = result["data"]["createWatchlist"]

      assert user_list["name"] == "My list"
      assert user_list["color"] == "BLACK"
      assert user_list["isPublic"] == false
      assert user_list["isScreener"]
      assert user_list["user"]["id"] == to_string(user.id)

      assert length(user_list["listItems"]) == 3
      assert %{"project" => %{"slug" => "dai"}} in user_list["listItems"]
      assert %{"project" => %{"slug" => "bitcoin"}} in user_list["listItems"]
      assert %{"project" => %{"slug" => "ethereum"}} in user_list["listItems"]
    end)
  end

  test "dynamic watchlist for market segments", %{conn: conn, user: user} do
    function = %{"name" => "market_segment", "args" => %{"market_segment" => "stablecoin"}}

    result = do_execute_mutation(conn, create_watchlist_query(function: function))
    user_list = result["data"]["createWatchlist"]

    assert user_list["name"] == "My list"
    assert user_list["color"] == "BLACK"
    assert user_list["isPublic"] == false
    assert user_list["user"]["id"] == to_string(user.id)

    assert %{"project" => %{"slug" => "dai"}} in user_list["listItems"]
    assert %{"project" => %{"slug" => "tether"}} in user_list["listItems"]
  end

  test "dynamic watchlist for top erc20 projects", %{conn: conn} do
    function = %{"name" => "top_erc20_projects", "args" => %{"size" => 2}}
    result = do_execute_mutation(conn, create_watchlist_query(function: function))
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

    result = do_execute_mutation(conn, create_watchlist_query(function: function))
    user_list = result["data"]["createWatchlist"]

    assert user_list["listItems"] == [
             %{"project" => %{"slug" => "maker"}},
             %{"project" => %{"slug" => "santiment"}}
           ]
  end

  test "dynamic watchlist for top all projects", %{conn: conn} do
    function = %{"name" => "top_all_projects", "args" => %{"size" => 3}}
    result = do_execute_mutation(conn, create_watchlist_query(function: function))
    user_list = result["data"]["createWatchlist"]

    assert user_list["listItems"] == [
             %{"project" => %{"slug" => "bitcoin"}},
             %{"project" => %{"slug" => "ethereum"}},
             %{"project" => %{"slug" => "xrp"}}
           ]
  end

  test "dynamic watchlist for min volume", %{conn: conn} do
    function = %{"name" => "min_volume", "args" => %{"min_volume" => 1_000_000_000}}
    result = do_execute_mutation(conn, create_watchlist_query(function: function))
    user_list = result["data"]["createWatchlist"]

    assert user_list["listItems"] == [
             %{"project" => %{"slug" => "bitcoin"}},
             %{"project" => %{"slug" => "ethereum"}},
             %{"project" => %{"slug" => "xrp"}},
             %{"project" => %{"slug" => "tether"}}
           ]
  end

  test "dynamic watchlist for slug list", %{conn: conn} do
    function = %{"name" => "slugs", "args" => %{"slugs" => ["bitcoin", "santiment"]}}
    result = do_execute_mutation(conn, create_watchlist_query(function: function))
    user_list = result["data"]["createWatchlist"]

    assert user_list["listItems"] == [
             %{"project" => %{"slug" => "bitcoin"}},
             %{"project" => %{"slug" => "santiment"}}
           ]
  end

  test "dynamic watchlist for currently trending projects", %{conn: conn} do
    with_mock(Sanbase.SocialData.TrendingWords,
      get_currently_trending_words: fn _, _ ->
        {:ok,
         [
           %{word: "SAN", score: 5},
           %{word: "bitcoin", score: 3},
           %{word: "xrp", score: 2},
           %{word: "random_str", score: 1}
         ]}
      end
    ) do
      function = %{"name" => "trending_projects"}
      result = do_execute_mutation(conn, create_watchlist_query(function: function))
      user_list = result["data"]["createWatchlist"]
      slugs = Enum.map(user_list["listItems"], fn %{"project" => %{"slug" => slug}} -> slug end)

      assert Enum.sort(slugs) == Enum.sort(["santiment", "bitcoin", "xrp"])
    end
  end

  defp create_watchlist_query(opts) do
    name = Keyword.get(opts, :name, "My list")
    color = Keyword.get(opts, :color, "BLACK")
    function = opts |> Keyword.get(:function) |> Jason.encode!()
    is_screener = Keyword.get(opts, :is_screener, false)

    ~s|
    mutation {
      createWatchlist(
        name: '#{name}'
        color: #{color}
        function: '#{function}'
        isScreener: #{is_screener}
        ) {
         id
         name
         color
         isPublic
         isScreener
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

  defp update_watchlist_query(opts) do
    id = Keyword.fetch!(opts, :id)
    function = opts |> Keyword.fetch!(:function) |> Jason.encode!()

    ~s|
    mutation {
      updateWatchlist(
        id: #{id},
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

  defp do_execute_mutation(conn, query) do
    conn
    |> post("/graphql", mutation_skeleton(query))
    |> json_response(200)
  end
end
