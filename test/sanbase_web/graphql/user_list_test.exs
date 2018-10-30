defmodule SanbaseWeb.Graphql.UserListTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Auth.User
  alias Sanbase.Model.Project
  alias Sanbase.Model.LatestCoinmarketcapData
  alias Sanbase.Repo
  alias Sanbase.UserLists.UserList

  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user =
      %User{
        salt: User.generate_salt(),
        privacy_policy_accepted: true
      }
      |> Repo.insert!()

    user2 =
      %User{
        salt: User.generate_salt(),
        privacy_policy_accepted: true
      }
      |> Repo.insert!()

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user, user2: user2}
  end

  test "create user list", %{user: user, conn: conn} do
    query = """
    mutation {
      createUserList(name: "My list", color: BLACK) {
        id,
        name,
        color,
        is_public,
        user {
          id
        },
        list_items {
          project {
            id
          }
        },
        inserted_at,
        updated_at
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    user_list = json_response(result, 200)["data"]["createUserList"]

    assert user_list["name"] == "My list"
    assert user_list["color"] == "BLACK"
    assert user_list["is_public"] == false
    assert user_list["user"]["id"] == user.id |> to_string()
  end

  test "update user list", %{user: user, conn: conn} do
    {:ok, created_user_list} = UserList.create_user_list(user, %{name: "My Test List"})

    project =
      Repo.insert!(%Project{name: "Santiment", ticker: "SAN", coinmarketcap_id: "santiment"})

    Repo.insert!(%LatestCoinmarketcapData{
      price_usd: 0.5,
      coinmarketcap_id: project.coinmarketcap_id,
      update_time: Ecto.DateTime.utc()
    })

    update_name = "My updated list"

    query = """
    mutation {
      updateUserList(
        id: #{created_user_list.id},
        name: "#{update_name}",
        color: BLACK,
        list_items: [{project_id: #{project.id}}]
      ) {
        name,
        color,
        is_public,
        user {
          id
        },
        list_items {
          project {
            id,
            priceUsd
          }
        }
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    user_list = json_response(result, 200)["data"]["updateUserList"]
    assert user_list["name"] == update_name
    assert user_list["color"] == "BLACK"
    assert user_list["is_public"] == false

    assert user_list["list_items"] == [
             %{"project" => %{"id" => project.id |> to_string(), "priceUsd" => 0.5}}
           ]
  end

  test "update user list - remove list items", %{user: user, conn: conn} do
    {:ok, created_user_list} = UserList.create_user_list(user, %{name: "My Test List"})

    project =
      Repo.insert!(%Project{name: "Santiment", ticker: "SAN", coinmarketcap_id: "santiment"})

    firstyiw_update_query = """
    mutation {
      updateUserList(
        id: #{created_user_list.id},
        list_items: [{project_id: #{project.id}}]
      ) {
        list_items {
          project {
            id
          }
        }
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(firstyiw_update_query))

    user_list = json_response(result, 200)["data"]["updateUserList"]
    assert user_list["list_items"] == [%{"project" => %{"id" => "#{project.id}"}}]

    update_name = "My updated list"

    second_update_query = """
    mutation {
      updateUserList(
        id: #{created_user_list.id},
        name: "#{update_name}",
        color: BLACK,
        list_items: []
      ) {
        name,
        color,
        is_public,
        user {
          id
        },
        list_items {
          project {
            id
          }
        }
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(second_update_query))

    user_list = json_response(result, 200)["data"]["updateUserList"]
    assert user_list["name"] == update_name
    assert user_list["color"] == "BLACK"
    assert user_list["is_public"] == false
    assert user_list["list_items"] == []
  end

  test "update user list - without list items", %{user: user, conn: conn} do
    {:ok, created_user_list} = UserList.create_user_list(user, %{name: "My Test List"})

    update_name = "My updated list"

    query = """
    mutation {
      updateUserList(
        id: #{created_user_list.id},
        name: "#{update_name}",
        color: BLACK,
      ) {
        name,
        color,
        is_public,
        user {
          id
        },
        list_items {
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

    user_list = json_response(result, 200)["data"]["updateUserList"]
    assert user_list["name"] == update_name
    assert user_list["color"] == "BLACK"
    assert user_list["is_public"] == false
    assert user_list["list_items"] == []
  end

  test "cannot update not own user list", %{user2: user2, conn: conn} do
    {:ok, created_user_list} = UserList.create_user_list(user2, %{name: "My Test List"})

    update_name = "My updated list"

    query = """
    mutation {
      updateUserList(
        id: #{created_user_list.id},
        name: "#{update_name}",
      ) {
        id
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    [error] = json_response(result, 200)["errors"]
    assert String.contains?(error["message"], "Cannot update user list")
  end

  test "remove user list", %{user: user, conn: conn} do
    {:ok, created_user_list} = UserList.create_user_list(user, %{name: "My Test List"})

    query = """
    mutation {
      removeUserList(
        id: #{created_user_list.id},
      ) {
        id
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(query))

    assert UserList.fetch_user_lists(user) == {:ok, []}
  end

  test "fetch user lists", %{user: user, conn: conn} do
    UserList.create_user_list(user, %{name: "My Test List"})

    query = query("fetchUserLists")

    result =
      conn
      |> post("/graphql", query_skeleton(query, "fetchUserLists"))

    user_list = json_response(result, 200)["data"]["fetchUserLists"] |> List.first()
    assert user_list["name"] == "My Test List"
    assert user_list["color"] == "NONE"
    assert user_list["is_public"] == false
    assert user_list["user"]["id"] == user.id |> to_string()
  end

  test "fetch public user lists", %{user: user, conn: conn} do
    UserList.create_user_list(user, %{name: "My Test List", is_public: true})

    query = query("fetchPublicUserLists")

    result =
      conn
      |> post("/graphql", query_skeleton(query, "fetchPublicUserLists"))

    user_list = json_response(result, 200)["data"]["fetchPublicUserLists"] |> List.first()
    assert user_list["name"] == "My Test List"
    assert user_list["color"] == "NONE"
    assert user_list["is_public"] == true
    assert user_list["user"]["id"] == user.id |> to_string()
  end

  test "fetch all public user lists", %{user: user, user2: user2, conn: conn} do
    UserList.create_user_list(user, %{name: "My Test List", is_public: true})
    UserList.create_user_list(user2, %{name: "My Test List", is_public: true})

    query = query("fetchAllPublicUserLists")

    result =
      conn
      |> post("/graphql", query_skeleton(query, "fetchAllPublicUserLists"))

    all_public_lists_cnt =
      json_response(result, 200)["data"]["fetchAllPublicUserLists"] |> Enum.count()

    assert all_public_lists_cnt == 2
  end

  describe "fetch_public_user_lists_by_id" do
    test "returns user list when public", %{user: user, conn: conn} do
      project =
        Repo.insert!(%Project{name: "Santiment", ticker: "SAN", coinmarketcap_id: "santiment"})

      {:ok, user_list} = UserList.create_user_list(user, %{name: "My Test List", is_public: true})

      {:ok, user_list} =
        UserList.update_user_list(%{id: user_list.id, list_items: [%{project_id: project.id}]})

      query = query("fetchPublicUserListsById(userListId: #{user_list.id})")

      result =
        conn
        |> post("/graphql", query_skeleton(query, "fetchPublicUserListsById"))

      user_list_result = json_response(result, 200)["data"]["fetchPublicUserListsById"]

      assert user_list_result == %{
               "color" => "NONE",
               "id" => "#{user_list.id}",
               "is_public" => true,
               "list_items" => [%{"project" => %{"id" => "#{project.id}"}}],
               "name" => "My Test List",
               "user" => %{"id" => "#{user.id}"}
             }
    end

    test "returns null when no public list is available", %{user: user, conn: conn} do
      {:ok, user_list} =
        UserList.create_user_list(user, %{name: "My Test List", is_public: false})

      query = query("fetchPublicUserListsById(userListId: #{user_list.id})")

      result =
        conn
        |> post("/graphql", query_skeleton(query, "fetchPublicUserListsById"))

      user_list_result = json_response(result, 200)["data"]["fetchPublicUserListsById"]

      assert user_list_result == nil
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
        list_items {
          project {
            id
          }
        }
      }
    }
    """
  end
end
