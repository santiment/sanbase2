defmodule SanbaseWeb.Graphql.ProjectsByFunctionTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    infr_eth = insert(:infrastructure, %{code: "ETH"})

    stablecoin = insert(:market_segment, %{name: "stablecoin"})
    coin = insert(:market_segment, %{name: "coin"})
    mineable = insert(:market_segment, %{name: "mineable"})

    insert(:project, %{ticker: "TUSD", coinmarketcap_id: "tether", market_segment: stablecoin})
    insert(:latest_cmc_data, %{coinmarketcap_id: "tether", rank: 4, volume_usd: 3_000_000_000})

    insert(:project, %{
      ticker: "DAI",
      coinmarketcap_id: "dai",
      market_segment: stablecoin,
      infrastructure: infr_eth,
      main_contract_address: "0x" <> Sanbase.TestUtils.random_string()
    })

    insert(:latest_cmc_data, %{coinmarketcap_id: "dai", rank: 40, volume_usd: 15_000_000})

    insert(:project, %{ticker: "ETH", coinmarketcap_id: "ethereum", market_segment: mineable})
    insert(:latest_cmc_data, %{coinmarketcap_id: "ethereum", rank: 2, volume_usd: 3_000_000_000})

    insert(:project, %{ticker: "BTC", coinmarketcap_id: "bitcoin", market_segment: mineable})
    insert(:latest_cmc_data, %{coinmarketcap_id: "bitcoin", rank: 1, volume_usd: 15_000_000_000})

    insert(:project, %{ticker: "XRP", coinmarketcap_id: "ripple", market_segment: mineable})
    insert(:latest_cmc_data, %{coinmarketcap_id: "ripple", rank: 3, volume_usd: 1_000_000_000})

    insert(:project, %{
      ticker: "MKR",
      coinmarketcap_id: "maker",
      market_segment: coin,
      infrastructure: infr_eth,
      main_contract_address: "0x" <> Sanbase.TestUtils.random_string()
    })

    insert(:latest_cmc_data, %{coinmarketcap_id: "maker", rank: 20, volume_usd: 150_000_000})

    insert(:project, %{
      ticker: "SAN",
      coinmarketcap_id: "santiment",
      market_segment: coin,
      infrastructure: infr_eth,
      main_contract_address: "0x" <> Sanbase.TestUtils.random_string()
    })

    insert(:latest_cmc_data, %{coinmarketcap_id: "santiment", rank: 95, volume_usd: 100_000})

    conn = build_conn()

    {:ok, conn: conn}
  end

  test "dynamic watchlist for market segments", %{conn: conn} do
    function = %{"name" => "market_segment", "args" => %{"market_segment" => "stablecoin"}}

    result = execute_query(conn, query(function))
    projects = result["data"]["allProjectsByFunction"]

    assert projects == [
             %{"slug" => "dai"},
             %{"slug" => "tether"}
           ]
  end

  test "dynamic watchlist for top erc20 projects", %{conn: conn} do
    function = %{"name" => "top_erc20_projects", "args" => %{"size" => 2}}
    result = execute_query(conn, query(function))
    projects = result["data"]["allProjectsByFunction"]

    assert projects == [
             %{"slug" => "maker"},
             %{"slug" => "dai"}
           ]
  end

  test "dynamic watchlist for top all projects", %{conn: conn} do
    function = %{"name" => "top_all_projects", "args" => %{"size" => 3}}
    result = execute_query(conn, query(function))
    projects = result["data"]["allProjectsByFunction"]

    assert projects == [
             %{"slug" => "bitcoin"},
             %{"slug" => "ethereum"},
             %{"slug" => "ripple"}
           ]
  end

  test "dynamic watchlist for min volume", %{conn: conn} do
    function = %{"name" => "min_volume", "args" => %{"min_volume" => 1_000_000_000}}
    result = execute_query(conn, query(function, [:volume_usd]))
    projects = result["data"]["allProjectsByFunction"]

    slugs = projects |> Enum.map(& &1["slug"])
    volumes = projects |> Enum.map(& &1["volumeUsd"])

    assert slugs == ["bitcoin", "ethereum", "ripple", "tether"]
    assert Enum.all?(volumes, &Kernel.>=(&1, 1_000_000_000))
  end

  test "dynamic watchlist for slug list", %{conn: conn} do
    function = %{"name" => "slugs", "args" => %{"slugs" => ["bitcoin", "santiment"]}}
    result = execute_query(conn, query(function))
    projects = result["data"]["allProjectsByFunction"]

    assert projects == [
             %{"slug" => "bitcoin"},
             %{"slug" => "santiment"}
           ]
  end

  defp query(function, additional_fields \\ []) when is_map(function) do
    function = function |> Jason.encode!()

    ~s|
    {
      allProjectsByFunction(
        function: '#{function}'
        ) {
         slug
         #{additional_fields |> Enum.join(" ")}
      }
    }
    |
    |> String.replace(~r|\"|, ~S|\\"|)
    |> String.replace(~r|'|, ~S|"|)
  end

  defp execute_query(conn, query) do
    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
