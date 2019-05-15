defmodule SanbaseWeb.Graphql.DynamicUserListTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user = insert(:user)

    infr_eth = insert(:infrastructure_eth)

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

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  test "dynamic watchlist for market segments", %{conn: conn, user: user} do
    function = %{"name" => "market_segment", "args" => %{"market_segment" => "stablecoin"}}

    result = execute_mutation(conn, query(function))
    user_list = result["data"]["createUserList"]

    assert user_list["name"] == "My list"
    assert user_list["color"] == "BLACK"
    assert user_list["isPublic"] == false
    assert user_list["user"]["id"] == user.id |> to_string()

    assert user_list["listItems"] == [
             %{"project" => %{"slug" => "dai"}},
             %{"project" => %{"slug" => "tether"}}
           ]
  end

  test "dynamic watchlist for top erc20 projects", %{conn: conn} do
    function = %{"name" => "top_erc20_projects", "args" => %{"size" => 2}}
    result = execute_mutation(conn, query(function))
    user_list = result["data"]["createUserList"]

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
    user_list = result["data"]["createUserList"]

    assert user_list["listItems"] == [
             %{"project" => %{"slug" => "maker"}},
             %{"project" => %{"slug" => "santiment"}}
           ]
  end

  test "dynamic watchlist for top all projects", %{conn: conn} do
    function = %{"name" => "top_all_projects", "args" => %{"size" => 3}}
    result = execute_mutation(conn, query(function))
    user_list = result["data"]["createUserList"]

    assert user_list["listItems"] == [
             %{"project" => %{"slug" => "bitcoin"}},
             %{"project" => %{"slug" => "ethereum"}},
             %{"project" => %{"slug" => "ripple"}}
           ]
  end

  test "dynamic watchlist for min volume", %{conn: conn} do
    function = %{"name" => "min_volume", "args" => %{"min_volume" => 1_000_000_000}}
    result = execute_mutation(conn, query(function))
    user_list = result["data"]["createUserList"]

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
    user_list = result["data"]["createUserList"]

    assert user_list["listItems"] == [
             %{"project" => %{"slug" => "bitcoin"}},
             %{"project" => %{"slug" => "santiment"}}
           ]
  end

  defp query(function, opts \\ []) when is_map(function) do
    name = Keyword.get(opts, :name, "My list")
    color = Keyword.get(opts, :color, "BLACK")
    function = function |> Jason.encode!()

    ~s|
    mutation {
      createUserList(
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
