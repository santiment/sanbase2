defmodule SanbaseWeb.Graphql.BlockchainAddressWatchlistApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.TestHelpers

  alias Sanbase.UserList

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    clean_task_supervisor_children()

    infr = insert(:infrastructure, code: "ETH")

    user = insert(:user)
    user2 = insert(:user)

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user, user2: user2, infr: infr}
  end

  test "create blockchain addresses watchlist", %{user: user, conn: conn} do
    eth_infrastructure = Sanbase.Repo.get_by(Sanbase.Model.Infrastructure, code: "ETH")
    insert(:project, slug: "ethereum", infrastructure: eth_infrastructure)

    query = """
    mutation {
      createWatchlist(
        type: BLOCKCHAIN_ADDRESS
        name: "My list"
        description: "Description"
        listItems: [
          {blockchainAddress: {address: "0xf4b51b14b9ee30dc37ec970b50a486f37686e2a8", infrastructure: "ETH", labels: ["Trader", "DEX"]}},
          {blockchainAddress: {address: "0x123b", infrastructure: "ETH", labels: ["Trader", "CEX"]}}
        ]
        color: BLACK) {
          id
          name
          description
          color
          isPublic
          user { id }
          listItems {
            blockchainAddress {
              address
              labels { name origin }
            }
          }
      }
    }
    """

    labels_rows = [
      [
        "0xf4b51b14b9ee30dc37ec970b50a486f37686e2a8",
        "centralized_exchange",
        ~s|{"comment":"Poloniex GNT","is_dex":false,"owner":"Poloniex","source":""}|
      ],
      [
        "0xf4b51b14b9ee30dc37ec970b50a486f37686e2a8",
        "whale",
        ~s|{"rank": 58, "value": 1.1438690681177702e+24}|
      ]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: labels_rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        conn
        |> post("/graphql", mutation_skeleton(query))
        |> json_response(200)

      watchlist = result["data"]["createWatchlist"]

      assert watchlist["name"] == "My list"
      assert watchlist["description"] == "Description"
      assert watchlist["color"] == "BLACK"
      assert watchlist["isPublic"] == false
      assert watchlist["user"]["id"] == user.id |> to_string()

      assert %{
               "blockchainAddress" => %{
                 "address" => "0xf4b51b14b9ee30dc37ec970b50a486f37686e2a8",
                 "labels" => [
                   %{"name" => "DEX", "origin" => "user"},
                   %{"name" => "Trader", "origin" => "user"},
                   %{"name" => "centralized_exchange", "origin" => "santiment"},
                   %{"name" => "whale", "origin" => "santiment"}
                 ]
               }
             } in watchlist["listItems"]

      assert %{
               "blockchainAddress" => %{
                 "address" => "0x123b",
                 "labels" => [
                   %{"name" => "CEX", "origin" => "user"},
                   %{"name" => "Trader", "origin" => "user"}
                 ]
               }
             } in watchlist["listItems"]
    end)
  end

  test "update blockchain address watchlist", %{user: user, conn: conn} do
    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: []}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      {:ok, watchlist} =
        UserList.create_user_list(user, %{name: "My Test List", type: :blockchain_address})

      update_name = "My updated list"
      update_description = "My updated description"

      query = """
      mutation {
        updateWatchlist(
          id: #{watchlist.id}
          name: "#{update_name}"
          description: "#{update_description}"
          color: BLACK
          listItems: [{blockchainAddress: {address: "0x123a", infrastructure: "ETH", notes: "note", labels: ["Trader", "DEX"]}}]
          isMonitored: true
        ) {
          name
          description
          color
          isPublic
          isMonitored
          user { id }
          listItems {
            blockchainAddress { address notes labels { name } }
          }
        }
      }
      """

      watchlist1 =
        conn
        |> post("/graphql", mutation_skeleton(query))
        |> json_response(200)
        |> get_in(["data", "updateWatchlist"])

      assert watchlist1["name"] == update_name
      assert watchlist1["description"] == update_description
      assert watchlist1["color"] == "BLACK"
      assert watchlist1["isPublic"] == false
      assert watchlist1["isMonitored"] == true

      assert watchlist1["listItems"] == [
               %{
                 "blockchainAddress" => %{
                   "address" => "0x123a",
                   "notes" => "note",
                   "labels" => [%{"name" => "DEX"}, %{"name" => "Trader"}]
                 }
               }
             ]

      query = """
      mutation {
        updateWatchlist(
          id: #{watchlist.id}
          name: "#{update_name}"
          description: "#{update_description}"
          color: BLACK
          listItems: [{blockchainAddress: {address: "0x123a", infrastructure: "ETH", notes: "note2", labels: ["Trader", "DEX"]}}]
          isMonitored: true
        ) {
          name
          description
          color
          isPublic
          isMonitored
          user { id }
          listItems {
            blockchainAddress { address notes labels { name } }
          }
        }
      }
      """

      watchlist2 =
        conn
        |> post("/graphql", mutation_skeleton(query))
        |> json_response(200)
        |> get_in(["data", "updateWatchlist"])

      assert watchlist2["name"] == update_name
      assert watchlist2["description"] == update_description
      assert watchlist2["color"] == "BLACK"
      assert watchlist2["isPublic"] == false
      assert watchlist2["isMonitored"] == true

      assert watchlist2["listItems"] == [
               %{
                 "blockchainAddress" => %{
                   "address" => "0x123a",
                   "notes" => "note2",
                   "labels" => [%{"name" => "DEX"}, %{"name" => "Trader"}]
                 }
               }
             ]
    end)
  end

  test "update blockchain address watchlist - remove list items", %{user: user, conn: conn} do
    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: []}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      {:ok, watchlist} =
        UserList.create_user_list(user, %{name: "My Test List", type: :blockchain_address})

      first_update = """
      mutation {
        updateWatchlist(
          id: #{watchlist.id},
          listItems: [{blockchainAddress: {address: "0x123a", infrastructure: "ETH"}}]
        ) {
          listItems {
            blockchainAddress {
              address
              labels { name }
            }
          }
        }
      }
      """

      result =
        conn
        |> post("/graphql", mutation_skeleton(first_update))
        |> json_response(200)

      updated_watchlist = result["data"]["updateWatchlist"]

      assert updated_watchlist["listItems"] == [
               %{
                 "blockchainAddress" => %{
                   "address" => "0x123a",
                   "labels" => []
                 }
               }
             ]

      second_update = """
      mutation {
        updateWatchlist(
          id: #{watchlist.id},
          listItems: []
        ) {
          listItems {
            blockchainAddress {
              address
            }
          }
        }
      }
      """

      result =
        conn
        |> post("/graphql", mutation_skeleton(second_update))

      updated_watchlist2 = json_response(result, 200)["data"]["updateWatchlist"]
      assert updated_watchlist2["listItems"] == []
    end)
  end

  test "update blockchain address watchlist - without list items", %{user: user, conn: conn} do
    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: []}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      {:ok, watchlist} =
        UserList.create_user_list(user, %{name: "My Test List", type: :blockchain_address})

      update_name = "My updated list"

      query = """
      mutation {
        updateWatchlist(
          id: #{watchlist.id},
          name: "#{update_name}",
          color: BLACK,
        ) {
          name,
          color,
          is_public,
          user {
            id
          },
          listItems {
            blockchainAddress {
              address
            }
          }
        }
      }
      """

      result =
        conn
        |> post("/graphql", mutation_skeleton(query))

      updated_watchlist = json_response(result, 200)["data"]["updateWatchlist"]
      assert updated_watchlist["name"] == update_name
      assert updated_watchlist["color"] == "BLACK"
      assert updated_watchlist["is_public"] == false
      assert updated_watchlist["listItems"] == []
    end)
  end

  test "cannot update not own watchlist", %{user2: user2, conn: conn} do
    {:ok, watchlist} =
      UserList.create_user_list(user2, %{name: "My Test List", type: :blockchain_address})

    update_name = "My updated list"

    query = """
    mutation {
      updateWatchlist(
        id: #{watchlist.id}
        name: "#{update_name}"
      ) {
        id
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))
      |> json_response(200)

    [error] = result["errors"]
    assert String.contains?(error["message"], "Cannot update watchlist belonging to another user")
  end

  test "remove watchlist", %{user: user, conn: conn} do
    {:ok, watchlist} =
      UserList.create_user_list(user, %{name: "My Test List", type: :blockchain_address})

    query = """
    mutation {
      removeWatchlist(
        id: #{watchlist.id},
      ) {
        id
      }
    }
    """

    _result =
      conn
      |> post("/graphql", mutation_skeleton(query))
      |> json_response(200)

    assert UserList.fetch_user_lists(user, :blockchain_address) == {:ok, []}
  end

  test "fetch blockchain address watchlists", %{user: user, conn: conn} do
    {:ok, _} = UserList.create_user_list(user, %{name: "My Test List", type: :blockchain_address})

    query = query("fetchWatchlists(type: BLOCKCHAIN_ADDRESS)")

    result =
      conn
      |> post("/graphql", query_skeleton(query, "fetchWatchlists"))
      |> json_response(200)

    watchlists = result["data"]["fetchWatchlists"]
    watchlist = watchlists |> List.first()

    assert length(watchlists) == 1
    assert watchlist["name"] == "My Test List"
    assert watchlist["color"] == "NONE"
    assert watchlist["is_public"] == false
    assert watchlist["user"]["id"] == user.id |> to_string()
  end

  test "fetch public watchlists", %{user: user, conn: conn} do
    {:ok, _} =
      UserList.create_user_list(user, %{
        name: "My Test List",
        is_public: true,
        type: :blockchain_address
      })

    query = query("fetchPublicWatchlists(type: BLOCKCHAIN_ADDRESS)")

    result =
      conn
      |> post("/graphql", query_skeleton(query, "fetchPublicWatchlists"))
      |> json_response(200)

    user_lists = result["data"]["fetchPublicWatchlists"] |> List.first()
    assert user_lists["name"] == "My Test List"
    assert user_lists["color"] == "NONE"
    assert user_lists["is_public"] == true
    assert user_lists["user"]["id"] == user.id |> to_string()
  end

  test "fetch all public watchlists", %{user: user, conn: conn} do
    insert(:watchlist, %{user: user, name: "n1", is_public: true, type: :blockchain_address})
    insert(:watchlist, %{user: user, name: "n2", is_public: true, type: :blockchain_address})

    query = query("fetchAllPublicWatchlists(type: BLOCKCHAIN_ADDRESS)")

    result =
      conn
      |> post("/graphql", query_skeleton(query, "fetchAllPublicWatchlists"))
      |> json_response(200)

    all_public_lists = result["data"]["fetchAllPublicWatchlists"]

    assert Enum.count(all_public_lists) == 2
  end

  test "fetch watchlist by slug", context do
    ws =
      insert(:watchlist, %{
        slug: "stablecoins",
        name: "Stablecoins",
        is_public: true,
        is_screener: true,
        type: :blockchain_address
      })

    query = """
    {
      watchlistBySlug(slug: "stablecoins") {
        id
        name
        slug
        isScreener
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(200)

    assert result["data"]["watchlistBySlug"]["id"] |> Sanbase.Math.to_integer() == ws.id
    assert result["data"]["watchlistBySlug"]["name"] == ws.name
    assert result["data"]["watchlistBySlug"]["slug"] == ws.slug
    assert result["data"]["watchlistBySlug"]["isScreener"]
  end

  test "returns public lists for anonymous users", %{user2: user} do
    {:ok, watchlist} =
      UserList.create_user_list(user, %{
        name: "My Test List",
        is_public: true,
        type: :blockchain_address
      })

    query = query("watchlist(id: #{watchlist.id})")

    result =
      post(build_conn(), "/graphql", query_skeleton(query, "watchlist"))
      |> json_response(200)

    assert result["data"]["watchlist"] == %{
             "color" => "NONE",
             "id" => "#{watchlist.id}",
             "is_public" => true,
             "is_screener" => false,
             "listItems" => [],
             "name" => "My Test List",
             "user" => %{"id" => "#{user.id}"}
           }
  end

  test "returns blockchain watchlist when public", %{user2: user, conn: conn} do
    {:ok, watchlist} =
      UserList.create_user_list(user, %{
        name: "My Test List",
        is_public: true,
        is_screener: false,
        type: :blockchain_address
      })

    query = query("watchlist(id: #{watchlist.id})")

    result =
      conn
      |> post("/graphql", query_skeleton(query, "watchlist"))
      |> json_response(200)

    assert result["data"]["watchlist"] == %{
             "color" => "NONE",
             "id" => "#{watchlist.id}",
             "is_public" => true,
             "is_screener" => false,
             "listItems" => [],
             "name" => "My Test List",
             "user" => %{"id" => "#{user.id}"}
           }
  end

  test "returns current user's private watchlist", %{user: user, conn: conn} do
    {:ok, watchlist} =
      UserList.create_user_list(user, %{
        name: "My Test List",
        is_public: false,
        type: :blockchain_address
      })

    query = query("watchlist(id: #{watchlist.id})")

    result =
      conn
      |> post("/graphql", query_skeleton(query, "watchlist"))
      |> json_response(200)

    assert result["data"]["watchlist"] == %{
             "color" => "NONE",
             "id" => "#{watchlist.id}",
             "is_public" => false,
             "is_screener" => false,
             "listItems" => [],
             "name" => "My Test List",
             "user" => %{"id" => "#{user.id}"}
           }
  end

  test "returns null when no public watchlist is available", %{user2: user2, conn: conn} do
    {:ok, watchlist} =
      UserList.create_user_list(user2, %{
        name: "My Test List",
        is_public: false,
        type: :blockchain_address
      })

    query = query("watchlist(id: #{watchlist.id})")

    result =
      conn
      |> post("/graphql", query_skeleton(query, "watchlist"))
      |> json_response(200)

    assert result["data"]["watchlist"] == nil
  end

  test "fetch balance of blockchain addresses in watchlists", context do
    %{user: user, conn: conn} = context

    watchlist = insert(:watchlist, type: :blockchain_address, is_public: true)

    addr1 = "0x04291180af677efd464432138d2a5d766a3898d4"
    addr2 = "0x00e6a95f6f438cbe873d0465e1a2533052e155f0"
    addr3 = "0x003b9fb45362194a35a30cf076c937b5f483dc73"

    UserList.update_user_list(user, %{
      id: watchlist.id,
      list_items: [
        %{blockchain_address: %{address: addr1, infrastructure: "ETH"}},
        %{blockchain_address: %{address: addr2, infrastructure: "ETH"}},
        %{blockchain_address: %{address: addr3, infrastructure: "ETH"}}
      ]
    })

    project = insert(:random_erc20_project, infrastructure: context.infr)

    query = """
    {
      watchlist(id: #{watchlist.id}){
        listItems{
          blockchainAddress{
            address
              balance(selector: {slug: "#{project.slug}"})
              balanceDominance(selector: {slug: "#{project.slug}"})
              balanceChange(selector: {slug: "#{project.slug}"}, from: "utc_now-1d", to: "utc_now"){
                balanceStart
                balanceEnd
                balanceChangeAmount
                balanceChangePercent
              }
          }
        }
      }
    }
    """

    current_balance_data = [
      %{address: addr1, balance: 100.0},
      %{address: addr2, balance: 200.0},
      %{address: addr3, balance: 300.0}
    ]

    balance_change_data = [
      %{
        address: addr1,
        balance_start: 50.0,
        balance_end: 100.0,
        balance_change_amount: 50.0,
        balance_change_percent: 100.0
      },
      %{
        address: addr2,
        balance_start: 50.0,
        balance_end: 200.0,
        balance_change_amount: 150.0,
        balance_change_percent: 300.0
      },
      %{
        address: addr3,
        balance_start: 66.0,
        balance_end: 300.0,
        balance_change_amount: 234.0,
        balance_change_percent: 354.55
      }
    ]

    Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.HistoricalBalance.current_balance/2,
      {:ok, current_balance_data}
    )
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.HistoricalBalance.balance_change/4,
      {:ok, balance_change_data}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        conn
        |> post("/graphql", query_skeleton(query))
        |> json_response(200)
        |> get_in(["data", "watchlist", "listItems"])

      assert %{
               "blockchainAddress" => %{
                 "address" => addr1,
                 "balance" => 100.0,
                 "balanceDominance" => 16.67,
                 "balanceChange" => %{
                   "balanceChangeAmount" => 50.0,
                   "balanceChangePercent" => 100.0,
                   "balanceEnd" => 100.0,
                   "balanceStart" => 50.0
                 }
               }
             } in result

      assert %{
               "blockchainAddress" => %{
                 "address" => addr2,
                 "balance" => 200.0,
                 "balanceDominance" => 33.33,
                 "balanceChange" => %{
                   "balanceChangeAmount" => 150.0,
                   "balanceChangePercent" => 300.0,
                   "balanceEnd" => 200.0,
                   "balanceStart" => 50.0
                 }
               }
             } in result

      assert %{
               "blockchainAddress" => %{
                 "address" => addr3,
                 "balance" => 300.0,
                 "balanceDominance" => 50.0,
                 "balanceChange" => %{
                   "balanceChangeAmount" => 234.0,
                   "balanceChangePercent" => 354.55,
                   "balanceEnd" => 300.0,
                   "balanceStart" => 66.0
                 }
               }
             } in result
    end)
  end

  defp query(query) do
    """
    {
      #{query} {
        id
        name
        color
        is_public
        is_screener
        user {
          id
        }
        listItems {
          blockchainAddress {
            address
            labels { name }
          }
        }
      }
    }
    """
  end
end
