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

  test "fetch public watchlists of a user", context do
    %{conn: conn, user: user} = context

    watchlist = insert(:watchlist, %{user: user, is_public: true})
    insert(:watchlist, %{user: user, is_public: false})

    result = get_user(conn, user)

    assert result == %{
             "data" => %{
               "getUser" => %{
                 "email" => "<email hidden>",
                 "followers" => %{"count" => 0, "users" => []},
                 "following" => %{"count" => 0, "users" => []},
                 "id" => "#{user.id}",
                 "insights" => [],
                 "triggers" => [],
                 "username" => "#{user.username}",
                 "watchlists" => [
                   %{"id" => "#{watchlist.id}"}
                 ]
               }
             }
           }
  end

  test "fetch public insights of a user", context do
    %{conn: conn, user: user} = context

    post = insert(:post, %{user: user, state: "approved", ready_state: "published"})
    insert(:post, %{user: user})

    result = get_user(conn, user)

    assert result == %{
             "data" => %{
               "getUser" => %{
                 "email" => "<email hidden>",
                 "followers" => %{"count" => 0, "users" => []},
                 "following" => %{"count" => 0, "users" => []},
                 "id" => "#{user.id}",
                 "insights" => [
                   %{"id" => "#{post.id}"}
                 ],
                 "triggers" => [],
                 "username" => "#{user.username}",
                 "watchlists" => []
               }
             }
           }
  end

  test "fetch public triggers of a user", context do
    %{conn: conn, user: user} = context

    user_trigger =
      insert(:user_trigger, %{
        user: user,
        trigger: %{title: "ASD", is_public: true, settings: trigger_settings()}
      })

    result = get_user(conn, user)

    assert result == %{
             "data" => %{
               "getUser" => %{
                 "email" => "<email hidden>",
                 "followers" => %{"count" => 0, "users" => []},
                 "following" => %{"count" => 0, "users" => []},
                 "id" => "#{user.id}",
                 "insights" => [],
                 "triggers" => [%{"id" => user_trigger.id}],
                 "username" => "#{user.username}",
                 "watchlists" => []
               }
             }
           }
  end

  test "fetch data for user that hides privacy data", context do
    %{conn: conn, user: user} = context

    result = get_user(conn, user)

    assert result == %{
             "data" => %{
               "getUser" => %{
                 "email" => "<email hidden>",
                 "followers" => %{"count" => 0, "users" => []},
                 "following" => %{"count" => 0, "users" => []},
                 "id" => "#{user.id}",
                 "insights" => [],
                 "triggers" => [],
                 "username" => "#{user.username}",
                 "watchlists" => []
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
                 "followers" => %{"count" => 0, "users" => []},
                 "following" => %{"count" => 0, "users" => []},
                 "id" => "#{user.id}",
                 "insights" => [],
                 "triggers" => [],
                 "username" => "#{user.username}",
                 "watchlists" => []
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
        watchlists{ id }
        followers{ count users { id } }
        following{ count users { id } }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query, "currentUser"))
    |> json_response(200)
  end

  defp trigger_settings() do
    %{
      "type" => "daily_active_addresses",
      "target" => %{"slug" => "santiment"},
      "channel" => "telegram",
      "time_window" => "1d",
      "operation" => %{"percent_up" => 300.0}
    }
  end
end
