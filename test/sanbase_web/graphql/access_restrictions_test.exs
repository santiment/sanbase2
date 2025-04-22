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
    get_access_restrictions(conn)
    |> Enum.each(fn restriction ->
      assert is_boolean(restriction["isDeprecated"]) == true

      if not is_nil(restriction["hardDeprecateAfter"]) do
        assert restriction["isDeprecated"] == true

        assert {:ok, %DateTime{}, _} = DateTime.from_iso8601(restriction["hardDeprecateAfter"])
      end
    end)
  end

  test "metrics have status", %{conn: conn} do
    {:ok, metric} = Sanbase.Metric.Registry.by_name("price_usd_5m", "timeseries")
    {:ok, _} = Sanbase.Metric.Registry.update(metric, %{status: "alpha"})
    Sanbase.Metric.Registry.refresh_stored_terms()

    get_access_restrictions_for_metrics(conn)
    |> Enum.each(fn restriction ->
      if restriction["name"] == "price_usd_5m" do
        assert restriction["status"] == "alpha"
      else
        assert restriction["status"] == "released"
      end
    end)
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

    for %{"isRestricted" => true} = restriction <- get_access_restrictions(conn) do
      from = restriction["restrictedFrom"]
      to = restriction["restrictedTo"]

      assert is_nil(from) ||
               iso_datetime_older_than_years(from, 5)

      assert is_nil(to) ||
               iso_datetime_newer_than_hours(to, 1)
    end
  end

  test "pro+ sanbase user", %{conn: conn, user: user} do
    insert(:subscription_pro_plus_sanbase, user: user)

    for %{"isRestricted" => true} = restriction <- get_access_restrictions(conn) do
      from = restriction["restrictedFrom"]
      to = restriction["restrictedTo"]

      assert is_nil(from) ||
               iso_datetime_older_than_years(from, 5)

      assert is_nil(to) ||
               iso_datetime_newer_than_hours(to, 1)
    end
  end

  test "business pro user", %{conn: conn, user: user} do
    insert(:subscription_business_pro_monthly, user: user)

    for %{"isRestricted" => true} = restriction <- get_access_restrictions(conn) do
      from = restriction["restrictedFrom"]
      to = restriction["restrictedTo"]

      assert is_nil(from) ||
               iso_datetime_older_than_years(from, 5)

      assert is_nil(to) ||
               iso_datetime_newer_than_hours(to, 1)
    end
  end

  test "business max user", %{conn: conn, user: user} do
    insert(:subscription_business_max_monthly, user: user)

    for %{"isRestricted" => true} = restriction <- get_access_restrictions(conn) do
      from = restriction["restrictedFrom"]
      to = restriction["restrictedTo"]

      assert is_nil(from) ||
               iso_datetime_older_than_years(from, 5)

      assert is_nil(to) ||
               iso_datetime_newer_than_hours(to, 1)
    end
  end

  defp get_access_restrictions(conn) do
    query = """
    {
      getAccessRestrictions {
        type
        name
        status
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

  defp get_access_restrictions_for_metrics(conn) do
    query = """
    {
      getAccessRestrictions(filter: METRIC){
        type
        name
        status
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

  # filter all the metrics that are restricted and lest than 5 years
  defp restricted_metrics(conn) do
    get_access_restrictions_for_metrics(conn)
    |> Enum.filter(fn restriction -> restriction["isRestricted"] end)
    |> Enum.filter(fn restriction ->
      not is_nil(restriction["restrictedFrom"]) &&
        not iso_datetime_older_than_years(restriction["restrictedFrom"], 5)
    end)
  end

  def iso_datetime_older_than_years(iso_datetime, years) do
    datetime = Sanbase.DateTimeUtils.from_iso8601!(iso_datetime)

    DateTime.compare(datetime, Timex.shift(Timex.now(), days: -(years * 365 + 1))) == :lt
  end

  def iso_datetime_newer_than_hours(iso_datetime, hours) do
    datetime = Sanbase.DateTimeUtils.from_iso8601!(iso_datetime)

    DateTime.compare(datetime, Timex.shift(Timex.now(), hours: hours)) == :gt
  end
end
