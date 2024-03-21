defmodule SanbaseWeb.Graphql.ProjectsByFunctionApiTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Clickhouse.MetricAdapter

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    infr_eth = insert(:infrastructure, %{code: "ETH"})

    stablecoin = insert(:market_segment, %{name: "stablecoin"})
    coin = insert(:market_segment, %{name: "coin"})
    mineable = insert(:market_segment, %{name: "mineable"})

    p1 =
      insert(:project, %{
        ticker: "TUSD",
        slug: "tether",
        coinmarketcap_id: "tether",
        market_segments: [stablecoin]
      })

    insert(:latest_cmc_data, %{coinmarketcap_id: "tether", rank: 4, volume_usd: 3_000_000_000})

    insert(:random_erc20_project, %{
      ticker: "DAI",
      slug: "dai",
      coinmarketcap_id: "dai",
      market_segments: [stablecoin],
      infrastructure: infr_eth
    })

    insert(:latest_cmc_data, %{coinmarketcap_id: "dai", rank: 40, volume_usd: 15_000_000})

    p2 =
      insert(:project, %{
        ticker: "ETH",
        slug: "ethereum",
        coinmarketcap_id: "ethereum",
        market_segments: [mineable]
      })

    insert(:latest_cmc_data, %{coinmarketcap_id: "ethereum", rank: 2, volume_usd: 3_000_000_000})

    p3 =
      insert(:project, %{
        ticker: "BTC",
        slug: "bitcoin",
        coinmarketcap_id: "bitcoin",
        market_segments: [mineable]
      })

    insert(:latest_cmc_data, %{coinmarketcap_id: "bitcoin", rank: 1, volume_usd: 15_000_000_000})

    p4 =
      insert(:project, %{
        ticker: "XRP",
        slug: "xrp",
        coinmarketcap_id: "xrp",
        market_segments: [mineable]
      })

    insert(:latest_cmc_data, %{coinmarketcap_id: "xrp", rank: 3, volume_usd: 1_000_000_000})

    insert(:random_erc20_project, %{
      ticker: "MKR",
      slug: "maker",
      coinmarketcap_id: "maker",
      market_segments: [coin],
      infrastructure: infr_eth
    })

    insert(:latest_cmc_data, %{coinmarketcap_id: "maker", rank: 20, volume_usd: 150_000_000})

    insert(:random_erc20_project, %{
      ticker: "SAN",
      slug: "santiment",
      coinmarketcap_id: "santiment",
      market_segments: [coin],
      infrastructure: infr_eth
    })

    insert(:latest_cmc_data, %{coinmarketcap_id: "santiment", rank: 95, volume_usd: 100_000})

    conn = build_conn()

    {:ok, conn: conn, p1: p1, p2: p2, p3: p3, p4: p4}
  end

  test "wrong metric name in order_by returns an error", context do
    %{conn: conn, p1: p1} = context

    function = %{
      "name" => "selector",
      "args" => %{
        "pagination" => %{"page" => 1, "pageSize" => 2},
        "orderBy" => %{
          "metric" => "aily_active_addresses",
          "from" => "#{Timex.shift(Timex.now(), days: -7)}",
          "to" => "#{Timex.now()}",
          "aggregation" => "#{:last}",
          "direction" => :asc
        }
      }
    }

    Sanbase.Mock.prepare_mock2(&MetricAdapter.slugs_by_filter/6, {:ok, [p1.slug]})
    |> Sanbase.Mock.prepare_mock2(&MetricAdapter.slugs_order/5, {:ok, [p1.slug]})
    |> Sanbase.Mock.run_with_mocks(fn ->
      error_msg =
        execute_query(conn, query(function))
        |> get_in(["errors", Access.at(0), "message"])

      assert error_msg =~
               "The metric 'aily_active_addresses' is not supported, is deprecated or is mistyped"

      assert error_msg =~ "Did you mean the timeseries metric 'daily_active_addresses'?"
    end)
  end

  test "wrong metric name in filters returns an error", context do
    %{conn: conn, p1: p1} = context

    function = %{
      "name" => "selector",
      "args" => %{
        "filters" => [
          %{
            "metric" => "rice_usd",
            "from" => "#{Timex.shift(Timex.now(), days: -7)}",
            "to" => "#{Timex.now()}",
            "aggregation" => "#{:last}",
            "operator" => "#{:greater_than_or_equal_to}",
            "threshold" => 10
          }
        ]
      }
    }

    Sanbase.Mock.prepare_mock2(&MetricAdapter.slugs_by_filter/6, {:ok, [p1.slug]})
    |> Sanbase.Mock.prepare_mock2(&MetricAdapter.slugs_order/5, {:ok, [p1.slug]})
    |> Sanbase.Mock.run_with_mocks(fn ->
      error_msg =
        execute_query(conn, query(function))
        |> get_in(["errors", Access.at(0), "message"])

      assert error_msg =~ "The metric 'rice_usd' is not supported, is deprecated or is mistyped"
      assert error_msg =~ "Did you mean the timeseries metric 'price_usd'?"
    end)
  end

  test "projects by function for selector", context do
    %{conn: conn, p1: p1, p2: p2, p3: p3, p4: p4} = context

    function = %{
      "name" => "selector",
      "args" => %{
        "pagination" => %{"page" => 1, "pageSize" => 2},
        "orderBy" => %{
          "metric" => "daily_active_addresses",
          "from" => "#{Timex.shift(Timex.now(), days: -7)}",
          "to" => "#{Timex.now()}",
          "aggregation" => "#{:last}",
          "direction" => :asc
        },
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
      &MetricAdapter.slugs_by_filter/6,
      {:ok, [p1.slug, p2.slug, p3.slug, p4.slug]}
    )
    |> Sanbase.Mock.prepare_mock2(
      &MetricAdapter.slugs_order/5,
      {:ok, [p1.slug, p2.slug, p3.slug, p4.slug]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        execute_query(conn, query(function))
        |> get_in(["data", "allProjectsByFunction"])

      projects = result["projects"]
      stats = result["stats"]

      assert stats == %{"projectsCount" => 4}
      assert length(projects) == 2
      slugs = Enum.map(projects, & &1["slug"])

      assert slugs == [p1.slug, p2.slug]
    end)
  end

  test "projects by function for selector with filersCombinator OR", context do
    %{conn: conn, p1: p1, p2: p2, p3: p3, p4: p4} = context

    function = %{
      "name" => "selector",
      "args" => %{
        "filtersCombinator" => :or,
        "filters" => [
          %{
            "metric" => "daily_active_addresses",
            "from" => "#{Timex.shift(Timex.now(), days: -7)}",
            "to" => "#{Timex.now()}",
            "aggregation" => "#{:last}",
            "operator" => "#{:greater_than_or_equal_to}",
            "threshold" => 100
          },
          %{
            "metric" => "nvt",
            "from" => "#{Timex.shift(Timex.now(), days: -7)}",
            "to" => "#{Timex.now()}",
            "aggregation" => "#{:last}",
            "operator" => "#{:greater_than}",
            "threshold" => 10
          }
        ]
      }
    }

    Sanbase.Mock.prepare_mock(MetricAdapter, :slugs_by_filter, fn
      "daily_active_addresses", _, _, _, _, _ -> {:ok, [p1.slug, p2.slug, p3.slug]}
      "nvt", _, _, _, _, _ -> {:ok, [p2.slug, p3.slug, p4.slug]}
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        execute_query(conn, query(function))
        |> get_in(["data", "allProjectsByFunction"])

      projects = result["projects"]
      stats = result["stats"]

      assert stats == %{"projectsCount" => 4}
      assert length(projects) == 4

      slugs = Enum.map(projects, & &1["slug"]) |> Enum.sort()
      assert slugs == [p1.slug, p2.slug, p3.slug, p4.slug] |> Enum.sort()
    end)
  end

  test "empty filter returns all projects", context do
    function = %{"name" => "selector", "args" => %{"filters" => []}}

    result =
      execute_query(context.conn, query(function))
      |> get_in(["data", "allProjectsByFunction", "projects"])

    projects_count = Sanbase.Project.List.projects_count()
    assert length(result) == projects_count
  end

  test "pagination works with empty filter", context do
    function = %{
      "name" => "selector",
      "args" => %{
        "filters" => [],
        "pagination" => %{"page" => 1, "page_size" => 5}
      }
    }

    result =
      execute_query(context.conn, query(function))
      |> get_in(["data", "allProjectsByFunction", "projects"])

    assert length(result) == 5
  end

  test "erc20 filter returns all erc20 projects", context do
    function = %{"name" => "selector", "args" => %{"filters" => [%{"name" => "erc20"}]}}

    result =
      execute_query(context.conn, query(function))
      |> get_in(["data", "allProjectsByFunction", "projects"])

    projects_count = Sanbase.Project.List.erc20_projects_count()
    assert length(result) == projects_count
  end

  test "pagination works with erc20 filter ", context do
    function = %{
      "name" => "selector",
      "args" => %{
        "filters" => [%{"name" => "erc20"}],
        "pagination" => %{"page" => 1, "page_size" => 3}
      }
    }

    result =
      execute_query(context.conn, query(function))
      |> get_in(["data", "allProjectsByFunction", "projects"])

    assert length(result) == 3
  end

  test "projects by function for market segments", %{conn: conn} do
    function = %{"name" => "market_segment", "args" => %{"market_segment" => "stablecoin"}}

    result = execute_query(conn, query(function))
    projects = result["data"]["allProjectsByFunction"]["projects"]
    slugs = Enum.map(projects, & &1["slug"]) |> Enum.sort()

    assert slugs == ["dai", "tether"]
  end

  test "projects by function for top erc20 projects", %{conn: conn} do
    function = %{"name" => "top_erc20_projects", "args" => %{"size" => 2}}
    result = execute_query(conn, query(function))
    projects = result["data"]["allProjectsByFunction"]["projects"]

    assert projects == [
             %{"slug" => "maker"},
             %{"slug" => "dai"}
           ]
  end

  test "projects by function for top all projects", %{conn: conn} do
    function = %{"name" => "top_all_projects", "args" => %{"size" => 3}}
    result = execute_query(conn, query(function))
    projects = result["data"]["allProjectsByFunction"]["projects"]

    assert projects == [
             %{"slug" => "bitcoin"},
             %{"slug" => "ethereum"},
             %{"slug" => "xrp"}
           ]
  end

  test "projects by function for min volume", %{conn: conn} do
    function = %{"name" => "min_volume", "args" => %{"min_volume" => 1_000_000_000}}
    result = execute_query(conn, query(function, [:volume_usd]))
    projects = result["data"]["allProjectsByFunction"]["projects"]

    slugs = projects |> Enum.map(& &1["slug"])
    volumes = projects |> Enum.map(& &1["volumeUsd"])

    assert slugs == ["bitcoin", "ethereum", "xrp", "tether"]
    assert Enum.all?(volumes, &Kernel.>=(&1, 1_000_000_000))
  end

  test "projects by function for slug list", %{conn: conn} do
    function = %{"name" => "slugs", "args" => %{"slugs" => ["bitcoin", "santiment"]}}
    result = execute_query(conn, query(function))
    projects = result["data"]["allProjectsByFunction"]["projects"]

    assert %{"slug" => "bitcoin"} in projects
    assert %{"slug" => "santiment"} in projects
  end

  defp query(function, additional_fields \\ []) when is_map(function) do
    function = function |> Jason.encode!()

    ~s| {
      allProjectsByFunction(
        function: '#{function}'
        ) {
         projects{
           slug
           #{additional_fields |> Enum.join(" ")}
         }
         stats{
           projectsCount
         }
      }
    } | |> String.replace(~r|\"|, ~S|\\"|) |> String.replace(~r|'|, ~S|"|)
  end
end
