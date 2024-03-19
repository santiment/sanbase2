defmodule SanbaseWeb.Plans.BusinessPlansTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user, email: "test@example.com")
    insert(:subscription_business_max_monthly, user: user)
    conn = setup_jwt_auth(build_conn(), user)
    {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(user)
    apikey_conn = setup_apikey_auth(build_conn(), apikey)

    business_pro_user = insert(:user, email: "test2@example.com")
    insert(:subscription_business_pro_monthly, user: business_pro_user)
    business_pro_conn = setup_jwt_auth(build_conn(), business_pro_user)
    {:ok, business_pro_apikey} = Sanbase.Accounts.Apikey.generate_apikey(business_pro_user)
    business_pro_apikey_conn = setup_apikey_auth(build_conn(), business_pro_apikey)

    [
      user: user,
      conn: conn,
      apikey: apikey,
      apikey_conn: apikey_conn,
      business_pro_user: business_pro_user,
      business_pro_conn: business_pro_conn,
      business_pro_apikey: business_pro_apikey,
      business_pro_apikey_conn: business_pro_apikey_conn
    ]
  end

  describe "API Limits per plan" do
    test "when anonymous user", _context do
      {:ok, quota} = Sanbase.ApiCallLimit.get_quota(:remote_ip, "1.1.1.1", :apikey)
      assert quota.api_calls_limits == %{month: 1000, minute: 100, hour: 500}
    end

    test "when plan is FREE", _context do
      user = insert(:user, email: "free@example.com")
      {:ok, quota} = Sanbase.ApiCallLimit.get_quota(:user, user, :apikey)
      assert quota.api_calls_limits == %{month: 1000, minute: 100, hour: 500}
    end

    test "when plan is Sanbase BASIC", _context do
      user = insert(:user, email: "sanbase_basic@example.com")
      insert(:subscription_basic_sanbase, user: user)
      {:ok, quota} = Sanbase.ApiCallLimit.get_quota(:user, user, :apikey)
      assert quota.api_calls_limits == %{month: 1000, minute: 100, hour: 500}
    end

    test "when plan is Sanbase PRO", _context do
      user = insert(:user, email: "sanbase_pro@example.com")
      insert(:subscription_pro_sanbase, user: user)
      {:ok, quota} = Sanbase.ApiCallLimit.get_quota(:user, user, :apikey)
      assert quota.api_calls_limits == %{month: 5000, minute: 100, hour: 1000}
    end

    test "when plan is Sanbase PRO+", _context do
      user = insert(:user, email: "sanbase_pro_plus@example.com")
      insert(:subscription_pro_plus_sanbase, user: user)
      {:ok, quota} = Sanbase.ApiCallLimit.get_quota(:user, user, :apikey)
      assert quota.api_calls_limits == %{month: 80000, minute: 100, hour: 4000}
    end

    test "when plan is Sanbase MAX", _context do
      user = insert(:user, email: "sanbase_max@example.com")
      insert(:subscription_max_sanbase, user: user)
      {:ok, quota} = Sanbase.ApiCallLimit.get_quota(:user, user, :apikey)
      assert quota.api_calls_limits == %{month: 80000, minute: 100, hour: 4000}
    end

    test "when plan is Sanapi PRO", _context do
      user = insert(:user, email: "api_pro@example.com")
      insert(:subscription_pro, user: user)
      {:ok, quota} = Sanbase.ApiCallLimit.get_quota(:user, user, :apikey)
      assert quota.api_calls_limits == %{month: 600_000, minute: 600, hour: 30000}
    end

    test "when plan is BUSINESS_PRO", _context do
      user = insert(:user, email: "api_business_pro@example.com")
      insert(:subscription_business_pro_monthly, user: user)
      {:ok, quota} = Sanbase.ApiCallLimit.get_quota(:user, user, :apikey)
      assert quota.api_calls_limits == %{month: 600_000, minute: 600, hour: 30000}
    end

    test "when plan is BUSINESS_MAX", _context do
      user = insert(:user, email: "api_business_max@example.com")
      insert(:subscription_business_max_monthly, user: user)
      {:ok, quota} = Sanbase.ApiCallLimit.get_quota(:user, user, :apikey)
      assert quota.api_calls_limits == %{month: 1_200_000, minute: 1200, hour: 60000}
    end

    test "when plan is Sanapi CUSTOM", _context do
      user = insert(:user, email: "api_custom@example.com")
      insert(:subscription_custom, user: user)
      {:ok, quota} = Sanbase.ApiCallLimit.get_quota(:user, user, :apikey)
      assert quota == %{quota: :infinity}
    end
  end

  describe "API restrictions per plan" do
    test "Anonymous user has 1 year historical data or and last 30 days missing", context do
      custom_access_metrics =
        Sanbase.Billing.Plan.MVRVAccess.get() |> Map.keys() |> Keyword.values()

      restricted =
        get_access_restrictions(build_conn())
        |> Enum.filter(fn r ->
          r["isRestricted"] and
            r["isAccessible"] and
            r["name"] not in custom_access_metrics
        end)

      for access <- restricted do
        restricted_from = Sanbase.DateTimeUtils.from_iso8601!(access["restrictedFrom"])
        restricted_to = Sanbase.DateTimeUtils.from_iso8601!(access["restrictedTo"])

        diff_in_days = DateTime.diff(DateTime.utc_now(), restricted_from, :day)
        diff_in_days_to = DateTime.diff(DateTime.utc_now(), restricted_to, :day)

        # ~1 year
        assert diff_in_days >= 1 * 365 - 1 and diff_in_days <= 1 * 365 + 1
        # ~30 days
        assert diff_in_days_to >= 30 - 1 and diff_in_days_to <= 30 + 1
      end
    end

    test "Registered user with FREE plan has 1 year historical data or and last 30 days missing",
         _context do
      custom_access_metrics =
        Sanbase.Billing.Plan.MVRVAccess.get() |> Map.keys() |> Keyword.values()

      user = insert(:user, email: "free@example.com")
      {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(user)
      apikey_conn = setup_apikey_auth(build_conn(), apikey)

      restricted =
        get_access_restrictions(apikey_conn)
        |> Enum.filter(fn r ->
          r["isRestricted"] and
            r["isAccessible"] and
            r["name"] not in custom_access_metrics
        end)

      for access <- restricted do
        restricted_from = Sanbase.DateTimeUtils.from_iso8601!(access["restrictedFrom"])
        restricted_to = Sanbase.DateTimeUtils.from_iso8601!(access["restrictedTo"])

        diff_in_days = DateTime.diff(DateTime.utc_now(), restricted_from, :day)
        diff_in_days_to = DateTime.diff(DateTime.utc_now(), restricted_to, :day)

        # ~1 year
        assert diff_in_days >= 1 * 365 - 1 and diff_in_days <= 1 * 365 + 1
        # ~30 days
        assert diff_in_days_to >= 30 - 1 and diff_in_days_to <= 30 + 1
      end
    end

    test "Sanbase PRO user has 1 year historical data or and last 30 days missing", _context do
      custom_access_metrics =
        Sanbase.Billing.Plan.MVRVAccess.get() |> Map.keys() |> Keyword.values()

      user = insert(:user, email: "sanbase_pro@example.com")
      insert(:subscription_pro_sanbase, user: user)
      {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(user)
      apikey_conn = setup_apikey_auth(build_conn(), apikey)

      # restricted metric is within historical and realtime data restrictions
      # min_plan=PRO are not accessible
      # not restricted are freely accessible
    end
  end

  test "BUSINESS_PRO user has access to metrics with min_plan=PRO", _context do
    api_pro_only_metric = fetch_api_metric_with_min_plan_pro()

    assert Sanbase.Billing.Plan.AccessChecker.plan_has_access?(
             "BUSINESS_PRO",
             "SANAPI",
             api_pro_only_metric
           )
  end

  test "BUSINESS_MAX user has access to metrics with min_plan=PRO", _context do
    api_pro_only_metric = fetch_api_metric_with_min_plan_pro()

    assert Sanbase.Billing.Plan.AccessChecker.plan_has_access?(
             "BUSINESS_MAX",
             "SANAPI",
             api_pro_only_metric
           )
  end

  test "BUSINESS_PRO after api call remaining count", context do
    make_api_call(context.business_pro_apikey_conn, [])
    |> json_response(200)

    {:ok, quota} = Sanbase.ApiCallLimit.get_quota(:user, context.business_pro_user, :apikey)
    assert quota.api_calls_remaining == %{month: 599_999, minute: 599, hour: 29999}
  end

  test "BUSINESS_MAX after api call remaining count", context do
    make_api_call(context.apikey_conn, [])
    |> json_response(200)

    {:ok, quota} = Sanbase.ApiCallLimit.get_quota(:user, context.user, :apikey)
    assert quota.api_calls_remaining == %{month: 1_199_999, minute: 1199, hour: 59999}
  end

  test "BUSINESS_MAX user no historical data or realtime restrictions", %{user: user} do
    {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(user)
    apikey_conn = setup_apikey_auth(build_conn(), apikey)

    for %{"isRestricted" => is_restrictred} <- get_access_restrictions(apikey_conn) do
      assert is_restrictred == false
    end
  end

  defp fetch_api_metric_with_min_plan_pro do
    Sanbase.Billing.ApiInfo.min_plan_map()
    |> Enum.filter(fn {_, min_plan} -> min_plan["SANAPI"] == "PRO" end)
    |> Enum.map(fn {metric_or_query_or_signal, _} -> metric_or_query_or_signal end)
    |> Enum.filter(fn tuple -> elem(tuple, 0) == :metric end)
    |> hd()
  end

  defp make_api_call(conn, extra_headers) do
    query = """
    { allProjects { slug } }
    """

    conn
    |> Sanbase.Utils.Conn.put_extra_req_headers(extra_headers)
    |> post("/graphql", query_skeleton(query))
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

  defp metric_resp() do
    {:ok,
     [
       %{value: 10.0, datetime: ~U[2019-01-01 00:00:00Z]},
       %{value: 20.0, datetime: ~U[2019-01-02 00:00:00Z]}
     ]}
  end
end
