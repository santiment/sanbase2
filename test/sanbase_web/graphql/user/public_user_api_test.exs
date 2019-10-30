defmodule SanbaseWeb.Graphql.PublicUserApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user = insert(:user)
    user2 = insert(:user)
    Sanbase.Auth.UserSettings.update_settings(user2, %{hide_privacy_data: false})

    {:ok, user: user, user2: user2}
  end

  test "fetch data for user that hides privacy data", context do
    %{conn: conn, user: user} = context

    result = get_user(conn, user)

    assert result == %{
             "data" => %{
               "getUser" => %{
                 "email" => "<hidden>",
                 "followers" => [],
                 "following" => [],
                 "id" => "#{user.id}",
                 "insights" => [],
                 "triggers" => [],
                 "username" => "#{user.username}"
               }
             }
           }
  end

  test "fetch data for user that does not hide privacy data", context do
    %{conn: conn, user2: user} = context

    result = get_user(conn, user)

    assert result == %{
             "data" => %{
               "getUser" => %{
                 "email" => "#{user.email}",
                 "followers" => [],
                 "following" => [],
                 "id" => "#{user.id}",
                 "insights" => [],
                 "triggers" => [],
                 "username" => "#{user.username}"
               }
             }
           }
  end

  defp get_user(conn, user) do
    query = """
    {
      getUser(selector: { id: #{user.id} }) {
        id
        email
        username
        insights{ id }
        triggers{ id }
        followers{ followerId }
        following{ followerId }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query, "currentUser"))
    |> json_response(200)
  end
end
