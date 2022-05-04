defmodule SanbaseWeb.Graphql.WatchlistApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.TestHelpers

  alias Sanbase.UserList
  alias Sanbase.Timeline.TimelineEvent
  alias Sanbase.Repo

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    clean_task_supervisor_children()

    user = insert(:user)
    user2 = insert(:user)

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user, user2: user2}
  end

  describe "watchlist voting" do
    test "vote and downvote", context do
      %{conn: conn} = context
      watchlist = insert(:watchlist, user: context.user)

      result = get_watchlist_votes(conn, watchlist.id)
      assert result["votedAt"] == nil

      assert result["votes"] == %{
               "currentUserVotes" => 0,
               "totalVoters" => 0,
               "totalVotes" => 0
             }

      %{"data" => %{"vote" => vote}} = vote(conn, watchlist.id, direction: :up)

      result = get_watchlist_votes(conn, watchlist.id)
      assert result["votedAt"] == vote["votedAt"]
      voted_at = vote["votedAt"] |> Sanbase.DateTimeUtils.from_iso8601!()
      assert Sanbase.TestUtils.datetime_close_to(voted_at, Timex.now(), seconds: 2)
      assert vote["votes"] == result["votes"]
      assert vote["votes"] == %{"currentUserVotes" => 1, "totalVoters" => 1, "totalVotes" => 1}

      %{"data" => %{"vote" => vote}} = vote(conn, watchlist.id, direction: :up)
      result = get_watchlist_votes(conn, watchlist.id)
      assert vote["votes"] == result["votes"]
      assert vote["votes"] == %{"currentUserVotes" => 2, "totalVoters" => 1, "totalVotes" => 2}

      %{"data" => %{"unvote" => vote}} = vote(conn, watchlist.id, direction: :down)
      result = get_watchlist_votes(conn, watchlist.id)
      assert vote["votes"] == result["votes"]
      assert vote["votes"] == %{"currentUserVotes" => 1, "totalVoters" => 1, "totalVotes" => 1}

      %{"data" => %{"unvote" => vote}} = vote(conn, watchlist.id, direction: :down)
      result = get_watchlist_votes(conn, watchlist.id)
      assert vote["votes"] == result["votes"]
      assert vote["votedAt"] == nil
      assert vote["votes"] == %{"currentUserVotes" => 0, "totalVoters" => 0, "totalVotes" => 0}
    end

    defp get_watchlist_votes(conn, watchlist_id) do
      query = """
      {
        watchlist(id: #{watchlist_id}){
          id
          votedAt
          votes { currentUserVotes totalVotes totalVoters }
        }
      }
      """

      conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(200)
      |> get_in(["data", "watchlist"])
    end

    defp vote(conn, watchlist_id, opts) do
      function =
        case Keyword.get(opts, :direction, :up) do
          :up -> "vote"
          :down -> "unvote"
        end

      mutation = """
      mutation {
        #{function}(watchlistId: #{watchlist_id}){
          votedAt
          votes { currentUserVotes totalVotes totalVoters }
        }
      }
      """

      conn
      |> post("/graphql", mutation_skeleton(mutation))
      |> json_response(200)
    end
  end

  test "create watchlist", %{user: user, conn: conn} do
    project = insert(:project)

    query = """
    mutation {
      createWatchlist(
        name: "My list"
        description: "Description"
        listItems: [{project_id: #{project.id}}]
        isScreener: true
        color: BLACK) {
          id
          name
          description
          color
          is_public
          user { id }
          listItems {
            project { id }
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
    assert watchlist["listItems"] == [%{"project" => %{"id" => "#{project.id}"}}]
  end

  test "update watchlist", %{user: user, conn: conn} do
    {:ok, watchlist} = UserList.create_user_list(user, %{name: "My Test List"})

    project = insert(:project)
    insert(:latest_cmc_data, %{coinmarketcap_id: project.slug, price_usd: 0.5})

    update_name = "My updated list"
    update_description = "My updated description"

    query = """
    mutation {
      updateWatchlist(
        id: #{watchlist.id}
        name: "#{update_name}"
        description: "#{update_description}"
        color: BLACK
        listItems: [{project_id: #{project.id}}]
        isMonitored: true
      ) {
        name
        description
        color
        isPublic
        isMonitored
        user { id }
        listItems {
          project { id priceUsd }
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
             %{"project" => %{"id" => project.id |> to_string(), "priceUsd" => 0.5}}
           ]
  end

  test "update watchlist - remove list items", %{user: user, conn: conn} do
    {:ok, watchlist} = UserList.create_user_list(user, %{name: "My Test List"})

    project = insert(:project)

    first_update = """
    mutation {
      updateWatchlist(
        id: #{watchlist.id},
        listItems: [{project_id: #{project.id}}]
      ) {
        listItems {
          project {
            id
          }
        }
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(first_update))

    updated_watchlist = json_response(result, 200)["data"]["updateWatchlist"]
    assert updated_watchlist["listItems"] == [%{"project" => %{"id" => "#{project.id}"}}]

    update_name = "My updated list"

    second_update = """
    mutation {
      updateWatchlist(
        id: #{watchlist.id},
        name: "#{update_name}",
        color: BLACK,
        listItems: []
      ) {
        name,
        color,
        is_public,
        user {
          id
        },
        listItems {
          project {
            id
          }
        }
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(second_update))

    updated_watchlist2 = json_response(result, 200)["data"]["updateWatchlist"]
    assert updated_watchlist2["name"] == update_name
    assert updated_watchlist2["color"] == "BLACK"
    assert updated_watchlist2["is_public"] == false
    assert updated_watchlist2["listItems"] == []
  end

  test "update watchlist - without list items", %{user: user, conn: conn} do
    {:ok, watchlist} = UserList.create_user_list(user, %{name: "My Test List"})

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
          project {
            id
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
    {:ok, watchlist} = UserList.create_user_list(user2, %{name: "My Test List"})

    update_name = "My updated list"

    query = """
    mutation {
      updateWatchlist(
        id: #{watchlist.id},
        name: "#{update_name}",
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
    {:ok, watchlist} = UserList.create_user_list(user, %{name: "My Test List"})

    remove_watchlist(conn, watchlist.id)

    assert UserList.fetch_user_lists(user, :project) == {:ok, []}
  end

  test "remove watchlist with vote", %{user: user, conn: conn} do
    {:ok, watchlist} = UserList.create_user_list(user, %{name: "My Test List"})
    vote(conn, watchlist.id, direction: :up)

    remove_watchlist(conn, watchlist.id)

    assert UserList.fetch_user_lists(user, :project) == {:ok, []}
  end

  test "remove watchlist twice in a row, returns proper error message", %{user: user, conn: conn} do
    {:ok, watchlist} = UserList.create_user_list(user, %{name: "My Test List"})

    remove_watchlist(conn, watchlist.id)

    assert UserList.fetch_user_lists(user, :project) == {:ok, []}

    result = remove_watchlist(conn, watchlist.id)

    [error] = result["errors"]

    assert String.contains?(
             error["message"],
             "Watchlist with id: #{watchlist.id} does not exist."
           )
  end

  test "fetch watchlists", %{user: user, conn: conn} do
    {:ok, _} = UserList.create_user_list(user, %{name: "My Test List"})

    query = query("fetchWatchlists")

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
    {:ok, _} = UserList.create_user_list(user, %{name: "My Test List", is_public: true})

    query = query("fetchPublicWatchlists")

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

  test "fetch all public watchlists", %{user: user, user2: user2, conn: conn} do
    {:ok, _} = UserList.create_user_list(user, %{name: "My Test List", is_public: true})
    {:ok, _} = UserList.create_user_list(user2, %{name: "My Test List", is_public: true})

    query = query("fetchAllPublicWatchlists")

    result =
      conn
      |> post("/graphql", query_skeleton(query, "fetchAllPublicWatchlists"))
      |> json_response(200)

    all_public_lists = result["data"]["fetchAllPublicWatchlists"]

    assert Enum.count(all_public_lists) == 2
  end

  describe "UserList" do
    test "fetch watchlist by slug", context do
      ws = insert(:watchlist, %{slug: "stablecoins", name: "Stablecoins", is_public: true})

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
      project = insert(:project)

      {:ok, watchlist} = UserList.create_user_list(user, %{name: "My Test List", is_public: true})

      {:ok, watchlist} =
        UserList.update_user_list(user, %{
          id: watchlist.id,
          list_items: [%{project_id: project.id}]
        })

      query = query("watchlist(id: #{watchlist.id})")

      result =
        post(build_conn(), "/graphql", query_skeleton(query, "watchlist"))
        |> json_response(200)

      assert result["data"]["watchlist"] == %{
               "color" => "NONE",
               "id" => "#{watchlist.id}",
               "is_public" => true,
               "listItems" => [%{"project" => %{"id" => "#{project.id}"}}],
               "name" => "My Test List",
               "user" => %{"id" => "#{user.id}"}
             }
    end

    test "returns watchlist when public", %{user2: user, conn: conn} do
      project = insert(:project)

      {:ok, watchlist} = UserList.create_user_list(user, %{name: "My Test List", is_public: true})

      {:ok, watchlist} =
        UserList.update_user_list(user, %{
          id: watchlist.id,
          list_items: [%{project_id: project.id}]
        })

      assert_receive({_, {:ok, %TimelineEvent{}}})

      assert TimelineEvent |> Repo.all() |> length() == 1

      query = query("watchlist(id: #{watchlist.id})")

      result =
        conn
        |> post("/graphql", query_skeleton(query, "watchlist"))
        |> json_response(200)

      assert result["data"]["watchlist"] == %{
               "color" => "NONE",
               "id" => "#{watchlist.id}",
               "is_public" => true,
               "listItems" => [%{"project" => %{"id" => "#{project.id}"}}],
               "name" => "My Test List",
               "user" => %{"id" => "#{user.id}"}
             }
    end

    test "returns current user's private watchlist", %{user: user, conn: conn} do
      project = insert(:project)

      {:ok, watchlist} =
        UserList.create_user_list(user, %{name: "My Test List", is_public: false})

      {:ok, watchlist} =
        UserList.update_user_list(user, %{
          id: watchlist.id,
          list_items: [%{project_id: project.id}]
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
               "listItems" => [%{"project" => %{"id" => "#{project.id}"}}],
               "name" => "My Test List",
               "user" => %{"id" => "#{user.id}"}
             }
    end

    test "returns null when no public watchlist is available", %{user2: user, conn: conn} do
      {:ok, watchlist} =
        UserList.create_user_list(user, %{name: "My Test List", is_public: false})

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
          project {
            id
          }
        }
      }
    }
    """
  end

  defp remove_watchlist(conn, id) do
    query = """
    mutation {
      removeWatchlist(
        id: #{id},
      ) {
        id
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(query))
    |> json_response(200)
  end
end
