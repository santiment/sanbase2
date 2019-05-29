defmodule SanbaseWeb.Graphql.UserListTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.TestHelpers

  alias Sanbase.Auth.User
  alias Sanbase.Model.Project
  alias Sanbase.Model.LatestCoinmarketcapData
  alias Sanbase.UserList
  alias Sanbase.Timeline.TimelineEvent

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    clean_task_supervisor_children()

    user = insert(:user)
    user2 = insert(:user)

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
    {:ok, user_list} = UserList.create_user_list(user, %{name: "My Test List"})

    project = insert(:project)
    insert(:latest_cmc_data, %{coinmarketcap_id: project.coinmarketcap_id, price_usd: 0.5})

    update_name = "My updated list"

    query = """
    mutation {
      updateUserList(
        id: #{user_list.id},
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
      |> json_response(200)

    user_list = result["data"]["updateUserList"]
    assert user_list["name"] == update_name
    assert user_list["color"] == "BLACK"
    assert user_list["is_public"] == false

    assert user_list["list_items"] == [
             %{"project" => %{"id" => project.id |> to_string(), "priceUsd" => 0.5}}
           ]
  end

  test "update user list - remove list items", %{user: user, conn: conn} do
    {:ok, created_user_list} = UserList.create_user_list(user, %{name: "My Test List"})

    project = insert(:project)

    first_update = """
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
      |> post("/graphql", mutation_skeleton(first_update))

    updated_user_list = json_response(result, 200)["data"]["updateUserList"]
    assert updated_user_list["list_items"] == [%{"project" => %{"id" => "#{project.id}"}}]

    update_name = "My updated list"

    second_update = """
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
      |> post("/graphql", mutation_skeleton(second_update))

    updated_user_list2 = json_response(result, 200)["data"]["updateUserList"]
    assert updated_user_list2["name"] == update_name
    assert updated_user_list2["color"] == "BLACK"
    assert updated_user_list2["is_public"] == false
    assert updated_user_list2["list_items"] == []
  end

  test "update user list - without list items", %{user: user, conn: conn} do
    {:ok, user_list} = UserList.create_user_list(user, %{name: "My Test List"})

    update_name = "My updated list"

    query = """
    mutation {
      updateUserList(
        id: #{user_list.id},
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

    updated_user_list = json_response(result, 200)["data"]["updateUserList"]
    assert updated_user_list["name"] == update_name
    assert updated_user_list["color"] == "BLACK"
    assert updated_user_list["is_public"] == false
    assert updated_user_list["list_items"] == []
  end

  test "cannot update not own user list", %{user2: user2, conn: conn} do
    {:ok, user_list} = UserList.create_user_list(user2, %{name: "My Test List"})

    update_name = "My updated list"

    query = """
    mutation {
      updateUserList(
        id: #{user_list.id},
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
    assert String.contains?(error["message"], "Cannot update user list")
  end

  test "remove user list", %{user: user, conn: conn} do
    {:ok, user_list} = UserList.create_user_list(user, %{name: "My Test List"})

    query = """
    mutation {
      removeUserList(
        id: #{user_list.id},
      ) {
        id
      }
    }
    """

    _result =
      conn
      |> post("/graphql", mutation_skeleton(query))
      |> json_response(200)

    assert UserList.fetch_user_lists(user) == {:ok, []}
  end

  test "fetch user lists", %{user: user, conn: conn} do
    {:ok, _} = UserList.create_user_list(user, %{name: "My Test List"})

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
    {:ok, _} = UserList.create_user_list(user, %{name: "My Test List", is_public: true})

    query = query("fetchPublicUserLists")

    result =
      conn
      |> post("/graphql", query_skeleton(query, "fetchPublicUserLists"))
      |> json_response(200)

    user_lists = result["data"]["fetchPublicUserLists"] |> List.first()
    assert user_lists["name"] == "My Test List"
    assert user_lists["color"] == "NONE"
    assert user_lists["is_public"] == true
    assert user_lists["user"]["id"] == user.id |> to_string()
  end

  test "fetch all public user lists", %{user: user, user2: user2, conn: conn} do
    {:ok, _} = UserList.create_user_list(user, %{name: "My Test List", is_public: true})
    {:ok, _} = UserList.create_user_list(user2, %{name: "My Test List", is_public: true})

    query = query("fetchAllPublicUserLists")

    result =
      conn
      |> post("/graphql", query_skeleton(query, "fetchAllPublicUserLists"))
      |> json_response(200)

    all_public_lists = result["data"]["fetchAllPublicUserLists"]

    assert Enum.count(all_public_lists) == 2
  end

  describe "UserList" do
    test "returns public lists for anonymous users", %{user2: user2} do
      project = insert(:project)

      {:ok, user_list} =
        UserList.create_user_list(user2, %{name: "My Test List", is_public: true})

      {:ok, user_list} =
        UserList.update_user_list(%{id: user_list.id(), list_items: [%{project_id: project.id}]})

      query = query("userList(userListId: #{user_list.id()})")

      result =
        post(build_conn(), "/graphql", query_skeleton(query, "userList"))
        |> json_response(200)

      assert result["data"]["userList"] == %{
               "color" => "NONE",
               "id" => "#{user_list.id()}",
               "is_public" => true,
               "list_items" => [%{"project" => %{"id" => "#{project.id}"}}],
               "name" => "My Test List",
               "user" => %{"id" => "#{user2.id}"}
             }
    end

    test "returns user list when public", %{user2: user2, conn: conn} do
      project = insert(:project)

      {:ok, user_list} =
        UserList.create_user_list(user2, %{name: "My Test List", is_public: true})

      {:ok, user_list} =
        UserList.update_user_list(%{id: user_list.id(), list_items: [%{project_id: project.id}]})

      assert_receive({_, {:ok, %TimelineEvent{}}})

      assert TimelineEvent |> Repo.all() |> length() == 1

      query = query("userList(userListId: #{user_list.id})")

      result =
        conn
        |> post("/graphql", query_skeleton(query, "userList"))
        |> json_response(200)

      assert result["data"]["userList"] == %{
               "color" => "NONE",
               "id" => "#{user_list.id()}",
               "is_public" => true,
               "list_items" => [%{"project" => %{"id" => "#{project.id}"}}],
               "name" => "My Test List",
               "user" => %{"id" => "#{user2.id}"}
             }
    end

    test "returns current user's private list", %{user: user, conn: conn} do
      project = insert(:project)

      {:ok, user_list} =
        UserList.create_user_list(user, %{name: "My Test List", is_public: false})

      {:ok, user_list} =
        UserList.update_user_list(%{id: user_list.id(), list_items: [%{project_id: project.id}]})

      query = query("userList(userListId: #{user_list.id()})")

      result =
        conn
        |> post("/graphql", query_skeleton(query, "userList"))
        |> json_response(200)

      assert result["data"]["userList"] == %{
               "color" => "NONE",
               "id" => "#{user_list.id()}",
               "is_public" => false,
               "list_items" => [%{"project" => %{"id" => "#{project.id}"}}],
               "name" => "My Test List",
               "user" => %{"id" => "#{user.id}"}
             }
    end

    test "returns null when no public list is available", %{user2: user2, conn: conn} do
      {:ok, user_list} =
        UserList.create_user_list(user2, %{name: "My Test List", is_public: false})

      query = query("userList(userListId: #{user_list.id()})")

      result =
        conn
        |> post("/graphql", query_skeleton(query, "userList"))
        |> json_response(200)

      assert result["data"]["userList"] == nil
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
