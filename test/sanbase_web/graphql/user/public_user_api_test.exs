defmodule SanbaseWeb.Graphql.PublicUserApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user = insert(:user)
    user2 = insert(:user)
    Sanbase.Accounts.UserSettings.update_settings(user2, %{hide_privacy_data: false})

    {:ok, user: user, user2: user2}
  end

  test "fetch user roles of public users", context do
    %{conn: conn, user: user} = context

    role_team = insert(:role_san_team)
    role_mod = insert(:role_san_moderator)

    insert(:user_role, user: user, role: role_team)
    insert(:user_role, user: user, role: role_mod)

    result = get_user(conn, user)

    assert %{"data" => %{"getUser" => %{"isSantimentTeamMember" => true, "isModerator" => true}}} =
             result
  end

  test "fetch subscriptions of public user", context do
    %{conn: conn, user: user} = context

    insert(:subscription_pro_sanbase, user: user)
    insert(:subscription_business_pro_monthly, user: user)

    result = get_user(conn, user)

    assert %{
             "data" => %{
               "getUser" => %{
                 "subscriptions" => public_user_subscriptions
               }
             }
           } = result

    assert length(public_user_subscriptions) == 2
    assert %{"productName" => "SANBASE", "planName" => "PRO"} in public_user_subscriptions
    assert %{"productName" => "SANAPI", "planName" => "BUSINESS_PRO"} in public_user_subscriptions
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
                 "insightsCount" => %{"totalCount" => 0, "pulseCount" => 0, "paywallCount" => 0},
                 "insights" => [],
                 "triggers" => [],
                 "username" => "#{user.username}",
                 "watchlists" => [
                   %{"id" => "#{watchlist.id}"}
                 ],
                 "chartConfigurations" => [],
                 "dashboards" => [],
                 "subscriptions" => [],
                 "isModerator" => false,
                 "isSantimentTeamMember" => false
               }
             }
           }
  end

  test "fetch public insights of a user", context do
    %{conn: conn, user: user} = context

    post =
      insert(:post, %{user: user, state: "approved", ready_state: "published", is_pulse: true})

    result = get_user(conn, user)

    assert result == %{
             "data" => %{
               "getUser" => %{
                 "email" => "<email hidden>",
                 "followers" => %{"count" => 0, "users" => []},
                 "following" => %{"count" => 0, "users" => []},
                 "id" => "#{user.id}",
                 "insightsCount" => %{"totalCount" => 1, "pulseCount" => 1, "paywallCount" => 0},
                 "insights" => [
                   %{"id" => post.id}
                 ],
                 "triggers" => [],
                 "username" => "#{user.username}",
                 "watchlists" => [],
                 "chartConfigurations" => [],
                 "dashboards" => [],
                 "subscriptions" => [],
                 "isModerator" => false,
                 "isSantimentTeamMember" => false
               }
             }
           }
  end

  test "fetch public triggers of a user", context do
    %{conn: conn, user: user} = context

    insert(:user_trigger, %{user: user, is_public: false})
    user_trigger = insert(:user_trigger, %{user: user, is_public: true})

    result = get_user(conn, user)

    assert result == %{
             "data" => %{
               "getUser" => %{
                 "email" => "<email hidden>",
                 "followers" => %{"count" => 0, "users" => []},
                 "following" => %{"count" => 0, "users" => []},
                 "id" => "#{user.id}",
                 "insightsCount" => %{"totalCount" => 0, "pulseCount" => 0, "paywallCount" => 0},
                 "insights" => [],
                 "triggers" => [%{"id" => user_trigger.id}],
                 "username" => "#{user.username}",
                 "watchlists" => [],
                 "chartConfigurations" => [],
                 "dashboards" => [],
                 "subscriptions" => [],
                 "isModerator" => false,
                 "isSantimentTeamMember" => false
               }
             }
           }
  end

  test "fetch public chart configurations of a user", context do
    %{conn: conn, user: user} = context

    insert(:chart_configuration, %{user: user, is_public: false})
    chart_configuration = insert(:chart_configuration, %{user: user, is_public: true})

    result = get_user(conn, user)

    assert result == %{
             "data" => %{
               "getUser" => %{
                 "email" => "<email hidden>",
                 "followers" => %{"count" => 0, "users" => []},
                 "following" => %{"count" => 0, "users" => []},
                 "id" => "#{user.id}",
                 "insightsCount" => %{"totalCount" => 0, "pulseCount" => 0, "paywallCount" => 0},
                 "insights" => [],
                 "triggers" => [],
                 "username" => "#{user.username}",
                 "watchlists" => [],
                 "chartConfigurations" => [%{"id" => chart_configuration.id}],
                 "dashboards" => [],
                 "subscriptions" => [],
                 "isModerator" => false,
                 "isSantimentTeamMember" => false
               }
             }
           }
  end

  test "fetch public dashboards of a user", context do
    %{conn: conn, user: user} = context

    insert(:dashboard, %{user: user, is_public: false})
    dashboard = insert(:dashboard, %{user: user, is_public: true})

    result = get_user(conn, user)

    assert result == %{
             "data" => %{
               "getUser" => %{
                 "email" => "<email hidden>",
                 "followers" => %{"count" => 0, "users" => []},
                 "following" => %{"count" => 0, "users" => []},
                 "id" => "#{user.id}",
                 "insightsCount" => %{"totalCount" => 0, "pulseCount" => 0, "paywallCount" => 0},
                 "insights" => [],
                 "triggers" => [],
                 "username" => "#{user.username}",
                 "watchlists" => [],
                 "chartConfigurations" => [],
                 "dashboards" => [%{"id" => dashboard.id}],
                 "subscriptions" => [],
                 "isModerator" => false,
                 "isSantimentTeamMember" => false
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
                 "insightsCount" => %{"totalCount" => 0, "pulseCount" => 0, "paywallCount" => 0},
                 "insights" => [],
                 "triggers" => [],
                 "username" => "#{user.username}",
                 "watchlists" => [],
                 "chartConfigurations" => [],
                 "dashboards" => [],
                 "subscriptions" => [],
                 "isModerator" => false,
                 "isSantimentTeamMember" => false
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
                 "insightsCount" => %{"totalCount" => 0, "pulseCount" => 0, "paywallCount" => 0},
                 "triggers" => [],
                 "username" => "#{user.username}",
                 "watchlists" => [],
                 "chartConfigurations" => [],
                 "dashboards" => [],
                 "subscriptions" => [],
                 "isModerator" => false,
                 "isSantimentTeamMember" => false
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
        insightsCount{ totalCount paywallCount pulseCount }
        insights{ id }
        triggers{ id }
        watchlists{ id }
        subscriptions{ planName productName }
        isModerator
        isSantimentTeamMember
        chartConfigurations{ id }
        dashboards{ id }
        followers{ count users { id } }
        following{ count users { id } }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query, "getUser"))
    |> json_response(200)
  end
end
