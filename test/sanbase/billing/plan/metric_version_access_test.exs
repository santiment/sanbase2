defmodule Sanbase.Billing.Plan.MetricVersionAccessTest do
  @moduledoc ~s"""
  How a subscription is matched against the plan access of a version. The GraphQL
  side (auth methods, messages, logging) is in
  `SanbaseWeb.Graphql.ApiMetricVersionAccessTest`.
  """
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import Sanbase.MetricVersionAliasHelpers, only: [ensure_seeded_versions!: 0]

  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Plan.MetricVersionAccess
  alias Sanbase.Billing.Subscription
  alias Sanbase.Metric.VersionAlias

  @metric "daily_active_addresses"

  setup do
    VersionAlias.clear_cache()
    ensure_seeded_versions!()
    :ok
  end

  describe "custom plans match the plan access of restricted_access_as_plan, with their own interval" do
    setup context do
      Sanbase.Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 9101")
      {:ok, _} = create_custom_plan(context, 9100, "CUSTOM_VERSIONS_BMAX", "BUSINESS_MAX")
      {:ok, _} = create_custom_plan(context, 9200, "CUSTOM_VERSIONS_PRO", "PRO")
      :ok
    end

    test "based on Business Max, yearly", context do
      ctx = apikey_context(context, "CUSTOM_VERSIONS_BMAX", "year")

      assert :ok == MetricVersionAccess.check(@metric, "2.0", ctx)
      assert :ok == MetricVersionAccess.check(@metric, "2.1", ctx)
    end

    test "based on Business Max, monthly", context do
      ctx = apikey_context(context, "CUSTOM_VERSIONS_BMAX", "month")

      assert :ok == MetricVersionAccess.check(@metric, "2.0", ctx)
      assert {:error, _} = MetricVersionAccess.check(@metric, "2.1", ctx)
    end

    test "based on PRO", context do
      ctx = apikey_context(context, "CUSTOM_VERSIONS_PRO", "year")

      assert :ok == MetricVersionAccess.check(@metric, "1.0", ctx)
      assert {:error, _} = MetricVersionAccess.check(@metric, "2.0", ctx)
    end
  end

  test "bundles match the plan access of their equivalent standard plan", context do
    ctx = apikey_context(context, "BUNDLE", "year")

    assert Plan.Bundle.equivalent_standard_plan() == "PRO"
    assert {:error, _} = MetricVersionAccess.check(@metric, "2.0", ctx)
  end

  test "internal calls, without a resolved product, are not restricted" do
    assert :ok == MetricVersionAccess.check(@metric, "9.9", %{})
  end

  defp apikey_context(context, plan_name, interval) do
    subscription = %Subscription{
      status: :active,
      plan: %Plan{name: plan_name, interval: interval, product_id: context.product_api.id}
    }

    %{auth: %{auth_method: :apikey, current_user: insert(:user), subscription: subscription}}
  end

  defp create_custom_plan(context, id, name, base_plan) do
    Plan.create_custom_api_plan(%{
      id: id,
      name: name,
      product_id: context.product_api.id,
      stripe_id: context.product_api.stripe_id,
      restrictions: %{
        restricted_access_as_plan: base_plan,
        api_call_limits: %{"minute" => 1000, "hour" => 100_000, "month" => 3_000_000},
        historical_data_in_days: 365,
        realtime_data_cut_off_in_days: 0,
        metric_access: %{"accessible" => "all", "not_accessible" => []},
        query_access: %{"accessible" => "all", "not_accessible" => []},
        signal_access: %{"accessible" => "all", "not_accessible" => []}
      },
      amount: 35_900,
      currency: "USD",
      interval: "year"
    })
  end
end
