defmodule Sanbase.Billing.Plan.CustomPlanTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup context do
    # The rest of the plans are inserted with hardcoded ids. Because of this
    # the plans_id_seq will generate id 1, which will cause a constraint error
    Sanbase.Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 1001")
    {:ok, plan} = create_custom_api_plan(context)
    user = insert(:user)
    _sub = insert(:subscription, user: user, plan_id: plan.id)
    {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(user)
    conn = setup_apikey_auth(build_conn(), apikey)

    %{
      plan: plan,
      user: user,
      conn: conn
    }
  end

  test "create custom plan", context do
    %{plan: plan} = context

    %{
      resolved_metrics: resolved_metrics,
      resolved_queries: resolved_queries,
      resolved_signals: resolved_signals,
      restrictions: _restrictions
    } =
      Sanbase.Billing.Plan.CustomPlan.Loader.get_data(
        plan.name,
        Sanbase.Billing.Product.code_by_id(plan.product_id)
      )

    assert "price_usd" in resolved_metrics
    assert "active_addresses_24h" in resolved_metrics
    assert "social_volume_total" in resolved_metrics
    assert "daily_active_addresses" not in resolved_metrics
    assert not Enum.any?(resolved_metrics, fn metric -> String.contains?(metric, "mvrv_usd") end)

    assert "current_user" in resolved_queries
    assert "all_projects" in resolved_queries
    assert "project_by_slug" in resolved_queries
    assert "history_price" not in resolved_queries
    assert not Enum.any?(resolved_queries, fn query -> String.contains?(query, "mvrv") end)

    assert Enum.sort(resolved_signals) ==
             Enum.sort(Sanbase.Signal.free_signals() ++ Sanbase.Signal.restricted_signals())

    assert resolved_metrics ==
             Sanbase.Billing.Plan.AccessChecker.get_available_metrics_for_plan(
               plan.name,
               "SANAPI",
               :all
             )

    assert %{
             "month" => 3_000_000,
             "hour" => 100_000,
             "minute" => 1000
           } ==
             Sanbase.Billing.Plan.CustomPlan.Access.api_call_limits(
               plan.name,
               Sanbase.Billing.Product.code_by_id(plan.product_id)
             )
  end

  test "custom plan access is cut to some metrics", context do
    %{conn: conn} = context

    project = insert(:random_project)

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: []}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      # mvrv_usd metrics are not accessible because of the pattern
      assert %{"errors" => [error]} = get_metric(conn, "mvrv_usd")

      assert error["message"] =~
               "metric mvrv_usd is not accessible with the currently used SANAPI CUSTOM_API_PLAN subscription"

      assert %{"errors" => [error]} = get_metric(conn, "daily_active_addresses")

      # mvrv_usd metrics are not accessible because of the explicit list
      assert error["message"] =~
               "metric daily_active_addresses is not accessible with the currently used SANAPI CUSTOM_API_PLAN subscription"

      # nvt is accessible
      assert get_metric(conn, "nvt", slug: project.slug, from: "utc_now-300d", to: "utc_now") ==
               %{
                 "data" => %{"getMetric" => %{"timeseriesData" => []}}
               }

      assert %{"errors" => [error]} =
               get_metric(conn, "nvt", from: "utc_now-370d", to: "utc_now-369d")

      assert error["message"] =~ "outside the allowed interval you can query"
    end)
  end

  test "custom plan access is cut to some queries", context do
    %{conn: conn, user: user} = context
    user_id = user.id |> to_string

    assert %{"errors" => [error]} = get_history_price(conn)

    assert error["message"] =~
             "query history_price is not accessible with the currently used SANAPI CUSTOM_API_PLAN subscription."

    assert %{"data" => %{"currentUser" => %{"id" => ^user_id}}} = get_current_user(conn)

    assert %{"errors" => [error]} =
             get_metric(conn, "nvt", from: "utc_now-370d", to: "utc_now-369d")

    assert error["message"] =~ "outside the allowed interval you can query"
  end

  defp create_custom_api_plan(context) do
    restrictions_args = %{
      name: "CUSTOM_PLAN_FOR_TEST",
      restricted_access_as_plan: "PRO",
      requested_product: "SANAPI",
      api_call_limits: %{"minute" => 1000, "hour" => 100_000, "month" => 3_000_000},
      historical_data_in_days: 365,
      realtime_data_cut_off_in_days: 0,
      metric_access: %{
        "accessible" => "all",
        "not_accessible" => ["daily_active_addresses"],
        "not_accessible_patterns" => ["mvrv_usd"]
      },
      query_access: %{
        "accessible" => "all",
        "not_accessible" => ["history_price"],
        "not_accessible_patterns" => ["mvrv"]
      },
      signal_access: %{
        "accessible" => "all",
        "not_accessible" => [],
        "not_accessible_patterns" => []
      }
    }

    {:ok, plan} =
      Sanbase.Billing.Plan.create_custom_api_plan(%{
        id: 1000,
        name: "CUSTOM_API_PLAN",
        product_id: context.product_api.id,
        stripe_id: context.product_api.stripe_id,
        restrictions: restrictions_args,
        amount: 35_900,
        currency: "USD",
        interval: "month"
      })

    {:ok, plan}
  end

  defp get_metric(conn, metric, opts \\ []) do
    slug = Keyword.get(opts, :slug, "bitcoin")
    from = Keyword.get(opts, :from, "utc_now-1d")
    to = Keyword.get(opts, :to, "utc_now")

    query =
      ~s|{ getMetric(metric: "#{metric}"){ timeseriesData(from: "#{from}", to: "#{to}", slug: "#{slug}") {value} } }|

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp get_current_user(conn) do
    conn
    |> post("/graphql", query_skeleton("{ currentUser{ id } }"))
    |> json_response(200)
  end

  defp get_history_price(conn) do
    query =
      ~s|{ historyPrice(slug: "bitcoin" from: "utc_now-1d" to: "utc_now" interval: "5m"){ priceUsd } }|

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
