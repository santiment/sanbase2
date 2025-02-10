defmodule SanbaseWeb.Graphql.AccessRestrictionsTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)

    conn = setup_jwt_auth(build_conn(), user)
    [user: user, conn: conn]
  end

  test "deprecated metrics", %{conn: conn} do
    conn
    |> get_access_restrictions()
    |> Enum.each(fn restriction ->
      assert is_boolean(restriction["isDeprecated"]) == true

      if not is_nil(restriction["hardDeprecateAfter"]) do
        assert restriction["isDeprecated"] == true

        assert {:ok, %DateTime{}, _} = DateTime.from_iso8601(restriction["hardDeprecateAfter"])
      end
    end)
  end

  test "free sanbase user", %{conn: conn} do
    days_ago = Timex.shift(DateTime.utc_now(), days: -29)
    over_two_years_ago = Timex.shift(DateTime.utc_now(), days: -(2 * 365 + 1))

    for %{"isRestricted" => true} = restriction <- get_access_restrictions(conn) do
      from = restriction["restrictedFrom"]
      to = restriction["restrictedTo"]

      assert is_nil(from) ||
               from
               |> Sanbase.DateTimeUtils.from_iso8601!()
               |> DateTime.compare(over_two_years_ago) == :gt

      assert is_nil(to) ||
               to
               |> Sanbase.DateTimeUtils.from_iso8601!()
               |> DateTime.compare(days_ago) == :lt
    end
  end

  test "pro sanbase user", %{conn: conn, user: user} do
    insert(:subscription_pro_sanbase, user: user)
    one_hour_ago = Timex.shift(DateTime.utc_now(), hours: -1)
    over_five_years_ago = Timex.shift(DateTime.utc_now(), days: -(5 * 365 + 1))

    for %{"isRestricted" => true} = restriction <- get_access_restrictions(conn) do
      from = restriction["restrictedFrom"]
      to = restriction["restrictedTo"]

      assert is_nil(from) ||
               from
               |> Sanbase.DateTimeUtils.from_iso8601!()
               |> DateTime.compare(over_five_years_ago) == :gt

      assert is_nil(to) ||
               to
               |> Sanbase.DateTimeUtils.from_iso8601!()
               |> DateTime.compare(one_hour_ago) == :lt
    end
  end

  test "pro+ sanbase user", %{conn: conn, user: user} do
    insert(:subscription_pro_plus_sanbase, user: user)
    one_hour_ago = Timex.shift(DateTime.utc_now(), hours: -1)
    over_five_years_ago = Timex.shift(DateTime.utc_now(), days: -(5 * 365 + 1))

    for %{"isRestricted" => true} = restriction <- get_access_restrictions(conn) do
      from = restriction["restrictedFrom"]
      to = restriction["restrictedTo"]

      assert is_nil(from) ||
               from
               |> Sanbase.DateTimeUtils.from_iso8601!()
               |> DateTime.compare(over_five_years_ago) == :gt

      assert is_nil(to) ||
               to
               |> Sanbase.DateTimeUtils.from_iso8601!()
               |> DateTime.compare(one_hour_ago) == :lt
    end
  end

  defp get_access_restrictions(conn) do
    query = """
    {
      getAccessRestrictions{
        type
        name
        minInterval
        internalName
        isRestricted
        restrictedFrom
        restrictedTo
        isDeprecated
        hardDeprecateAfter
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "getAccessRestrictions"])
  end
end
