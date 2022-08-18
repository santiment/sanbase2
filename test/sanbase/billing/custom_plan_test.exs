defmodule Sanbase.Billing.Plan.CustomPlanTest do
  use Sanbase.DataCase, async: false

  setup do
    # The rest of the plans are inserted with hardcoded ids. Because of this
    # the plans_id_seq will generate id 1, which will cause a constraint error
    Sanbase.Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 1001")

    %{}
  end

  test "create custom plan", context do
    restrictions_args = %{
      name: "CUSTOM_PLAN_FOR_TEST",
      restricted_access_as_plan: "PRO",
      product_code: "SANAPI",
      api_call_limits: %{"minute" => 1000, "hour" => 100_000, "month" => 3_000_000},
      historical_data_in_days: 365,
      realtime_data_cut_off_in_days: 1,
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

    %{
      resolved_metrics: resolved_metrics,
      resolved_queries: resolved_queries,
      resolved_signals: resolved_signals,
      restrictions: _restrictions
    } = Sanbase.Billing.Plan.CustomPlan.Loader.get_data(plan.name)

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
           } == Sanbase.Billing.Plan.CustomPlan.Access.api_call_limits(plan.name)
  end
end
