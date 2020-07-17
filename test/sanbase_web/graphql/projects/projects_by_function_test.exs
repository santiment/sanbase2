defmodule SanbaseWeb.Graphql.ProjectsByFunctionTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    infr_eth = insert(:infrastructure, %{code: "ETH"})

    stablecoin = insert(:market_segment, %{name: "stablecoin"})
    coin = insert(:market_segment, %{name: "coin"})
    mineable = insert(:market_segment, %{name: "mineable"})

    p1 = insert(:project, %{ticker: "TUSD", slug: "tether", market_segment: stablecoin})
    insert(:latest_cmc_data, %{coinmarketcap_id: "tether", rank: 4, volume_usd: 3_000_000_000})

    insert(:random_erc20_project, %{
      ticker: "DAI",
      slug: "dai",
      market_segment: stablecoin,
      infrastructure: infr_eth
    })

    insert(:latest_cmc_data, %{coinmarketcap_id: "dai", rank: 40, volume_usd: 15_000_000})

    p2 = insert(:project, %{ticker: "ETH", slug: "ethereum", market_segment: mineable})
    insert(:latest_cmc_data, %{coinmarketcap_id: "ethereum", rank: 2, volume_usd: 3_000_000_000})

    p3 = insert(:project, %{ticker: "BTC", slug: "bitcoin", market_segment: mineable})
    insert(:latest_cmc_data, %{coinmarketcap_id: "bitcoin", rank: 1, volume_usd: 15_000_000_000})

    p4 = insert(:project, %{ticker: "XRP", slug: "ripple", market_segment: mineable})
    insert(:latest_cmc_data, %{coinmarketcap_id: "ripple", rank: 3, volume_usd: 1_000_000_000})

    insert(:random_erc20_project, %{
      ticker: "MKR",
      slug: "maker",
      market_segment: coin,
      infrastructure: infr_eth
    })

    insert(:latest_cmc_data, %{coinmarketcap_id: "maker", rank: 20, volume_usd: 150_000_000})

    insert(:random_erc20_project, %{
      ticker: "SAN",
      slug: "santiment",
      market_segment: coin,
      infrastructure: infr_eth
    })

    insert(:latest_cmc_data, %{coinmarketcap_id: "santiment", rank: 95, volume_usd: 100_000})

    conn = build_conn()

    {:ok, conn: conn, p1: p1, p2: p2, p3: p3, p4: p4}
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
      &Sanbase.Metric.slugs_by_filter/6,
      {:ok, [p1.slug, p2.slug, p3.slug, p4.slug]}
    )
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.Metric.slugs_order/5,
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
             %{"slug" => "ripple"}
           ]
  end

  test "projects by function for min volume", %{conn: conn} do
    function = %{"name" => "min_volume", "args" => %{"min_volume" => 1_000_000_000}}
    result = execute_query(conn, query(function, [:volume_usd]))
    projects = result["data"]["allProjectsByFunction"]["projects"]

    slugs = projects |> Enum.map(& &1["slug"])
    volumes = projects |> Enum.map(& &1["volumeUsd"])

    assert slugs == ["bitcoin", "ethereum", "ripple", "tether"]
    assert Enum.all?(volumes, &Kernel.>=(&1, 1_000_000_000))
  end

  test "projects by function for slug list", %{conn: conn} do
    function = %{"name" => "slugs", "args" => %{"slugs" => ["bitcoin", "santiment"]}}
    result = execute_query(conn, query(function))
    projects = result["data"]["allProjectsByFunction"]["projects"]

    assert projects == [
             %{"slug" => "bitcoin"},
             %{"slug" => "santiment"}
           ]
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

  defp execute_query(conn, query) do
    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
