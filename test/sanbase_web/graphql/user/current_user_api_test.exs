defmodule SanbaseWeb.Graphql.CurrentUserApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    %{user: user, conn: conn}
  end

  test "get current user data", context do
    %{conn: conn, user: user} = context

    watchlist = insert(:watchlist, %{user: user, is_public: false})
    watchlist2 = insert(:watchlist, %{user: user, is_public: true})

    post = insert(:post, %{user: user, state: "approved", ready_state: "published"})
    post2 = insert(:post, %{user: user, ready_state: "draft"})

    user_trigger = insert(:user_trigger, %{user: user})
    user_trigger2 = insert(:user_trigger, %{user: user})

    chart_configuration = insert(:chart_configuration, user: user, is_public: true)
    chart_configuration2 = insert(:chart_configuration, user: user, is_public: false)

    dashboard = insert(:dashboard, user: user, is_public: true)
    dashboard2 = insert(:dashboard, user: user, is_public: false)

    result = conn |> get_user() |> get_in(["data", "currentUser"])

    assert result["email"] == user.email
    assert result["username"] == user.username

    assert result["followers"] == %{"count" => 0, "users" => []}
    assert result["following"] == %{"count" => 0, "users" => []}
    assert result["id"] == "#{user.id}"

    # Insights
    assert %{"id" => post.id} in result["insights"]
    assert %{"id" => post2.id} in result["insights"]

    # Triggers
    assert %{"id" => user_trigger.id} in result["triggers"]
    assert %{"id" => user_trigger2.id} in result["triggers"]

    # Watchlists
    assert %{"id" => "#{watchlist.id}"} in result["watchlists"]
    assert %{"id" => "#{watchlist2.id}"} in result["watchlists"]

    # Chart Configurations
    assert %{"id" => chart_configuration.id} in result["chartConfigurations"]
    assert %{"id" => chart_configuration2.id} in result["chartConfigurations"]

    # Dashboards
    assert %{"id" => dashboard.id} in result["dashboards"]
    assert %{"id" => dashboard2.id} in result["dashboards"]
  end

  describe "eligible_for_sanbase_trial" do
    test "eligible when user doesn't have sanbase subscription", context do
      result = context.conn |> get_user() |> get_in(["data", "currentUser"])
      assert result["isEligibleForSanbaseTrial"]
    end

    test "not eligible when user already has sanbase subscription", context do
      insert(:subscription_pro_sanbase, user: context.user)
      result = context.conn |> get_user() |> get_in(["data", "currentUser"])
      refute result["isEligibleForSanbaseTrial"]
    end
  end

  describe "signupDatetime" do
    test "when user is registered returns the signup datetime", _context do
      registration_dt = DateTime.utc_now(:second)

      user =
        insert(:user, registration_state: %{"state" => "finished", "datetime" => registration_dt})

      conn = setup_jwt_auth(build_conn(), user)
      result = conn |> get_user() |> get_in(["data", "currentUser"])
      assert result["signupDatetime"] == DateTime.to_iso8601(registration_dt)
    end

    test "when user has no registration_state - returns nil", _context do
      user = insert(:user)
      conn = setup_jwt_auth(build_conn(), user)
      result = conn |> get_user() |> get_in(["data", "currentUser"])
      assert result["signupDatetime"] == nil
    end
  end

  defp get_user(conn) do
    query = """
    {
      currentUser {
        id
        email
        username
        insights{ id }
        triggers{ id }
        watchlists{ id }
        dashboards{ id }
        chartConfigurations{ id }
        followers{ count users { id } }
        following{ count users { id } }
        isEligibleForSanbaseTrial
        signupDatetime
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query, "currentUser"))
    |> json_response(200)
  end
end
