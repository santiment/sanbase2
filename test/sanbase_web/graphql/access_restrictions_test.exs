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

    for %{is_restricted: true} = restriction <- get_access_restrictions(conn) do
      from = restriction["availableFrom"] |> Sanbase.DateTimeUtils.from_erl!()
      to = restriction["availableTo"] |> Sanbase.DateTimeUtils.from_erl!()

      assert DateTime.compare(from, over_two_years_ago) == :gt
      assert DateTime.compare(to, days_ago) == :lt
    end

    get_access_restrictions(conn)
  end

  test "pro sanbase user", %{conn: conn, user: user} do
    insert(:subscription_pro_sanbase, user: user)
    one_hour_ago = Timex.shift(Timex.now(), hours: -1)
    over_five_years_ago = Timex.shift(Timex.now(), days: -(5 * 365 + 1))

    for %{is_restricted: true} = restriction <- get_access_restrictions(conn) do
      from = restriction["availableFrom"] |> Sanbase.DateTimeUtils.from_erl!()
      to = restriction["availableTo"] |> Sanbase.DateTimeUtils.from_erl!()

      assert DateTime.compare(from, over_five_years_ago) == :gt
      assert DateTime.compare(to, one_hour_ago) == :lt
    end
  end

  # Premium API users don't have restrictions
  test "premium api user", %{user: user} do
    insert(:subscription_premium, user: user)
    {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(user)
    apikey_conn = setup_apikey_auth(build_conn(), apikey)

    for %{is_restricted: is_restrictred} <- get_access_restrictions(apikey_conn) do
      assert is_restrictred == false
    end
  end

  defp get_access_restrictions(conn) do
    query = """
    {
      getAccessRestrictions{
        type
        name
        isRestricted
        restrictedFrom
        restrictedTo
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
