defmodule SanbaseWeb.Graphql.AccessRestrictionsTest do
  use SanbaseWeb.ConnCase, async: true

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

  @tag capture_log: true
  test "metrics have status", %{conn: conn} do
    {:ok, metric} = Sanbase.Metric.Registry.by_name("price_usd_5m", "timeseries")
    {:ok, _} = Sanbase.Metric.Registry.update(metric, %{status: "alpha"})
    Sanbase.Metric.Registry.refresh_stored_terms()

    get_access_restrictions_for_metrics(conn)
    |> Enum.each(fn restriction ->
      case restriction["name"] do
        "price_usd_5m" ->
          assert restriction["status"] == "alpha"

        "price_usd" ->
          assert restriction["status"] == "released"

        _ ->
          assert restriction["status"] in ["alpha", "beta", "released"]
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

  describe "plan_name argument" do
    test "using plan_name with a standard plan works", %{conn: conn} do
      result = get_access_restrictions_with_plan_name(conn, "PRO")
      assert is_list(result)
      assert length(result) > 0
    end

    test "using plan_name returns different restrictions than FREE", %{conn: conn} do
      free_restrictions = get_access_restrictions_with_plan_name(conn, "FREE")
      pro_restrictions = get_access_restrictions_with_plan_name(conn, "PRO")

      free_accessible_count =
        Enum.count(free_restrictions, fn r -> r["isAccessible"] end)

      pro_accessible_count =
        Enum.count(pro_restrictions, fn r -> r["isAccessible"] end)

      assert pro_accessible_count >= free_accessible_count
    end

    test "using plan_name with a custom plan works", %{conn: conn} = context do
      plan_name = "CUSTOM_TEST_#{System.unique_integer([:positive])}"

      {:ok, plan} =
        %Sanbase.Billing.Plan{
          id: System.unique_integer([:positive]) + 100_000,
          name: plan_name,
          product_id: context.product_api.id,
          stripe_id: context.product_api.stripe_id,
          amount: 10_000,
          currency: "USD",
          interval: "month",
          is_deprecated: false,
          is_private: true,
          has_custom_restrictions: true,
          restrictions: %Sanbase.Billing.Plan.CustomPlan.Restrictions{
            restricted_access_as_plan: "PRO",
            api_call_limits: %{"minute" => 100, "hour" => 1000, "month" => 10_000},
            metric_access: %{
              "accessible" => ["price_usd"],
              "not_accessible" => [],
              "not_accessible_patterns" => []
            },
            query_access: %{
              "accessible" => "all",
              "not_accessible" => [],
              "not_accessible_patterns" => []
            },
            signal_access: %{
              "accessible" => "all",
              "not_accessible" => [],
              "not_accessible_patterns" => []
            }
          }
        }
        |> Sanbase.Repo.insert()

      product_code = Sanbase.Billing.Product.code_by_id(plan.product_id)

      on_exit(fn ->
        :persistent_term.erase({Sanbase.Billing.Plan.CustomPlan.Loader, plan.name, product_code})
      end)

      restrictions =
        get_access_restrictions_with_plan_name(conn, plan_name, product: "SANAPI")

      metric_restrictions =
        Enum.filter(restrictions, fn r -> r["type"] == "metric" end)

      accessible_metrics =
        metric_restrictions
        |> Enum.filter(fn r -> r["isAccessible"] end)
        |> Enum.map(fn r -> r["name"] end)

      assert "price_usd" in accessible_metrics

      not_accessible_metrics =
        metric_restrictions
        |> Enum.reject(fn r -> r["isAccessible"] end)
        |> Enum.map(fn r -> r["name"] end)

      assert "daily_active_addresses" in not_accessible_metrics
    end

    test "providing both plan and plan_name returns an error", %{conn: conn} do
      query = """
      {
        getAccessRestrictions(plan: PRO, planName: "MAX") {
          type
          name
          isRestricted
          isAccessible
        }
      }
      """

      result =
        conn
        |> post("/graphql", query_skeleton(query))
        |> json_response(200)

      assert %{"errors" => [error]} = result
      assert error["message"] =~ "Both 'plan' and 'plan_name' arguments are provided"
    end

    test "invalid plan_name returns an error", %{conn: conn} do
      query = """
      {
        getAccessRestrictions(planName: "GARBAGE") {
          type
          name
          isRestricted
          isAccessible
        }
      }
      """

      result =
        conn
        |> post("/graphql", query_skeleton(query))
        |> json_response(200)

      assert %{"errors" => [error]} = result
      assert error["message"] =~ "Invalid plan name: GARBAGE"
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

  defp get_access_restrictions_with_plan_name(conn, plan_name, opts \\ []) do
    product_arg =
      case Keyword.get(opts, :product) do
        nil -> ""
        product -> ", product: #{product}"
      end

    query = """
    {
      getAccessRestrictions(planName: "#{plan_name}"#{product_arg}) {
        type
        name
        isRestricted
        isAccessible
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

  def iso_datetime_older_than_years(iso_datetime, years) do
    datetime = Sanbase.DateTimeUtils.from_iso8601!(iso_datetime)

    DateTime.compare(datetime, Timex.shift(Timex.now(), days: -(years * 365 + 1))) == :lt
  end

  def iso_datetime_newer_than_hours(iso_datetime, hours) do
    datetime = Sanbase.DateTimeUtils.from_iso8601!(iso_datetime)

    DateTime.compare(datetime, Timex.shift(Timex.now(), hours: hours)) == :gt
  end
end
