defmodule Sanbase.Billing.Plan.MetricVersionAccessTest do
  @moduledoc ~s"""
  How a subscription is matched against the plan access of a version. The GraphQL
  side (auth methods, messages, logging) is in
  `SanbaseWeb.Graphql.ApiMetricVersionAccessTest`.
  """
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import Sanbase.MetricVersionAliasHelpers, only: [create_alias!: 1, ensure_seeded_versions!: 0]

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
      grant_pro_only!()
      ctx = apikey_context(context, "CUSTOM_VERSIONS_PRO", "year")

      assert :ok == MetricVersionAccess.check(@metric, "1.0", ctx)
      assert :ok == MetricVersionAccess.check(@metric, "7.0", ctx)
      assert {:error, _} = MetricVersionAccess.check(@metric, "2.0", ctx)
    end
  end

  test "bundles match the plan access of their equivalent standard plan", context do
    grant_pro_only!()
    ctx = apikey_context(context, "BUNDLE", "year")

    assert Plan.Bundle.equivalent_standard_plan() == "PRO"
    assert :ok == MetricVersionAccess.check(@metric, "7.0", ctx)
    assert {:error, _} = MetricVersionAccess.check(@metric, "2.0", ctx)
  end

  test "a SanAPI bundle that is FREE in the web app is judged without its interval or trial",
       context do
    create_alias!(%{
      version_num: "7.0",
      version_name: "seven:v1",
      plan_access: [
        %{product: "SANAPI", plan: "ANY"},
        %{product: "SANBASE", plan: "ANY", accessible_if_trial: false}
      ]
    })

    create_alias!(%{
      version_num: "8.0",
      version_name: "eight:v1",
      plan_access: [%{product: "SANBASE", plan: "ANY", billing_interval: "year"}]
    })

    # The auth plug answers a bundle in the web app as Bundle.sanbase_equivalent_plan/0
    ctx = %{
      auth: %{
        auth_method: :user_token,
        current_user: insert(:user),
        plan: "FREE",
        subscription: %Subscription{
          status: :trialing,
          plan: %Plan{name: "BUNDLE", interval: "year", product_id: context.product_api.id}
        }
      },
      requested_product_id: Sanbase.Billing.Product.product_sanbase()
    }

    assert :ok == MetricVersionAccess.check(@metric, "7.0", ctx)
    assert {:error, message} = MetricVersionAccess.check(@metric, "8.0", ctx)
    assert message =~ "Your plan (SanAPI BUNDLE, which is FREE on Sanbase)"
  end

  test "a request that did not go through the auth plug is anonymous" do
    # A GraphQL document over the websocket has no auth in its context
    for context <- [%{}, %{pubsub: SanbaseWeb.Endpoint, loader: nil}] do
      assert :ok == MetricVersionAccess.check(@metric, "1.0", context)
      assert {:error, _} = MetricVersionAccess.check(@metric, "2.0", context)
      assert MetricVersionAccess.usable_versions(@metric, ["1.0", "2.0"], context) == ["1.0"]
    end
  end

  # Only SanAPI PRO, so a caller matched as anything else (FREE) is denied.
  defp grant_pro_only!() do
    create_alias!(%{
      version_num: "7.0",
      version_name: "seven:v1",
      plan_access: [%{product: "SANAPI", plan: "PRO"}]
    })
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
