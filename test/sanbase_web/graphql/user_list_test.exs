defmodule SanbaseWeb.Graphql.UserListTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Auth.User
  alias Sanbase.Model.Project
  alias Sanbase.Repo

  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user =
      %User{
        salt: User.generate_salt(),
        privacy_policy_accepted: true
      }
      |> Repo.insert!()

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  test "create user list", %{user: user, conn: conn} do
    query = """
    mutation {
      createUserList(name: "My list", is_public: true, color: "black") {
        id,
        name,
        color,
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

    user_list = json_response(result, 200)["data"]["createUserList"] |> IO.inspect()

    assert user_list["name"] == "My list"
  end
end
