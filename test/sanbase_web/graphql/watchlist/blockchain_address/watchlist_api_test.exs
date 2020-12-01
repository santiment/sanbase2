defmodule SanbaseWeb.Graphql.BlockchainAddressWatchlistApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.TestHelpers

  alias Sanbase.UserList

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    clean_task_supervisor_children()

    insert(:infrastructure, code: "ETH")

    user = insert(:user)
    user2 = insert(:user)

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user, user2: user2}
  end

  test "create blockchain addresses watchlist", %{user: user, conn: conn} do
    query = """
    mutation {
      createWatchlist(
        type: BLOCKCHAIN_ADDRESS
        name: "My list"
        description: "Description"
        listItems: [
          {blockchainAddress: {address: "0x123a", infrastructure: "ETH", labels: ["Trader", "DEX"]}},
          {blockchainAddress: {address: "0x123b", infrastructure: "ETH", labels: ["Trader", "CEX"]}}
        ]
        color: BLACK) {
          id
          name
          description
          color
          is_public
          user { id }
          listItems {
            blockchainAddress {
              address
              labels { name}
            }
          }
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))
      |> json_response(200)

    watchlist = result["data"]["createWatchlist"]

    assert watchlist["name"] == "My list"
    assert watchlist["description"] == "Description"
    assert watchlist["color"] == "BLACK"
    assert watchlist["is_public"] == false
    assert watchlist["user"]["id"] == user.id |> to_string()

    assert %{
             "blockchainAddress" => %{
               "address" => "0x123a",
               "labels" => [%{"name" => "Trader"}, %{"name" => "DEX"}]
             }
           } in watchlist["listItems"]

    assert %{
             "blockchainAddress" => %{
               "address" => "0x123b",
               "labels" => [%{"name" => "Trader"}, %{"name" => "CEX"}]
             }
           } in watchlist["listItems"]
  end

  test "update blockchain address watchlist", %{user: user, conn: conn} do
    {:ok, watchlist} =
      UserList.create_user_list(user, %{name: "My Test List", type: :blockchain_address})

    # insert(:latest_cmc_data, %{coinmarketcap_id: project.slug, price_usd: 0.5})

    update_name = "My updated list"
    update_description = "My updated description"

    query = """
    mutation {
      updateWatchlist(
        id: #{watchlist.id}
        name: "#{update_name}"
        description: "#{update_description}"
        color: BLACK
        listItems: [{blockchainAddress: {address: "0x123a", infrastructure: "ETH", labels: ["Trader", "DEX"]}}]
        isMonitored: true
      ) {
        name
        description
        color
        isPublic
        isMonitored
        user { id }
        listItems {
          blockchainAddress { address labels { name } }
        }
      }
    }
    """

    watchlist =
      conn
      |> post("/graphql", mutation_skeleton(query))
      |> json_response(200)
      |> get_in(["data", "updateWatchlist"])

    assert watchlist["name"] == update_name
    assert watchlist["description"] == update_description
    assert watchlist["color"] == "BLACK"
    assert watchlist["isPublic"] == false
    assert watchlist["isMonitored"] == true

    assert watchlist["listItems"] == [
             %{
               "blockchainAddress" => %{
                 "address" => "0x123a",
                 "labels" => [%{"name" => "Trader"}, %{"name" => "DEX"}]
               }
             }
           ]
  end

  test "update blockchain address watchlist - remove list items", %{user: user, conn: conn} do
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
  end

  test "update blockchain address watchlist - without list items", %{user: user, conn: conn} do
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
    assert String.contains?(error["message"], "Cannot update watchlist of another user")
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

  describe "UserList" do
    test "fetch watchlist by slug", context do
      ws =
        insert(:watchlist, %{
          slug: "stablecoins",
          name: "Stablecoins",
          is_public: true,
          type: :blockchain_address
        })

      query = """
      {
        watchlistBySlug(slug: "stablecoins") {
          id
          name
          slug
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
  end

  defp query(query) do
    """
    {
      #{query} {
        id,
        name,
        color,
        is_public,
        user {
          id
        },
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
