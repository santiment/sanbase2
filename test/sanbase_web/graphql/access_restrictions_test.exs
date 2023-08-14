defmodule SanbaseWeb.Graphql.AccessRestrictionsTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)

    conn = setup_jwt_auth(build_conn(), user)
    [user: user, conn: conn]
  end

  test "free sanbase user", %{conn: conn} do
    days_ago = Timex.shift(Timex.now(), days: -29)
    over_two_years_ago = Timex.shift(Timex.now(), days: -(2 * 365 + 1))

    for %{"isRestricted" => true} = restriction <- get_access_restrictions(conn) do
      from = restriction["restrictedFrom"]
      to = restriction["restrictedTo"]

      assert is_nil(from) ||
               Sanbase.DateTimeUtils.from_iso8601!(from)
               |> DateTime.compare(over_two_years_ago) == :gt

      assert is_nil(to) ||
               Sanbase.DateTimeUtils.from_iso8601!(to)
               |> DateTime.compare(days_ago) == :lt
    end
  end

  test "pro sanbase user", %{conn: conn, user: user} do
    insert(:subscription_pro_sanbase, user: user)
    one_hour_ago = Timex.shift(Timex.now(), hours: -1)
    over_five_years_ago = Timex.shift(Timex.now(), days: -(5 * 365 + 1))

    for %{"isRestricted" => true} = restriction <- get_access_restrictions(conn) do
      from = restriction["restrictedFrom"]
      to = restriction["restrictedTo"]

      assert is_nil(from) ||
               Sanbase.DateTimeUtils.from_iso8601!(from)
               |> DateTime.compare(over_five_years_ago) == :gt

      assert is_nil(to) ||
               Sanbase.DateTimeUtils.from_iso8601!(to)
               |> DateTime.compare(one_hour_ago) == :lt
    end
  end

  # Premium API users don't have restrictions
  test "premium api user", %{user: user} do
    insert(:subscription_premium, user: user)
    {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(user)
    apikey_conn = setup_apikey_auth(build_conn(), apikey)

    for %{"isRestricted" => is_restrictred} <- get_access_restrictions(apikey_conn) do
      assert is_restrictred == false
    end
  end

  defp get_access_restrictions(conn) do
    query = """
    {
      getAccessRestrictions{
        type
        name
        internalName
        isRestricted
        restrictedFrom
        restrictedTo
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "getAccessRestrictions"])
  end
end
