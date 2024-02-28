defmodule SanbaseWeb.Plans.BusinessMAXTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user, email: "test@example.com")
    insert(:subscription_business_max_monthly, user: user)
    conn = setup_jwt_auth(build_conn(), user)
    {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(user)
    apikey_conn = setup_apikey_auth(build_conn(), apikey)

    [user: user, conn: conn, apikey: apikey, apikey_conn: apikey_conn]
  end

  test "BUSINESS_MAX user has access to metrics with min_plan=PRO", %{conn: conn, user: user} do
    api_pro_only_metric = fetch_api_metric_with_min_plan_pro()

    assert Sanbase.Billing.Plan.AccessChecker.plan_has_access?(
             "BUSINESS_MAX",
             "SANAPI",
             api_pro_only_metric
           )
  end

  test "BUSINESS_MAX after api call remaining count", context do
    result =
      make_api_call(context.apikey_conn, [])
      |> json_response(200)

    {:ok, quota} = Sanbase.ApiCallLimit.get_quota(:user, context.user, :apikey)
    assert quota.api_calls_remaining == %{month: 1_199_999, minute: 1199, hour: 59999}
  end

  test "BUSINESS_MAX user no historical data or realtime restrictions", %{user: user} do
    insert(:subscription_premium, user: user)
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
