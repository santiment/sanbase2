defmodule Sanbase.Billing.Plan.MetricVersionBucketsTest do
  @moduledoc ~s"""
  The metric version entitlement matrix: which plans get which version buckets.
  """
  use Sanbase.DataCase, async: false

  alias Sanbase.Billing.Plan.AccessChecker

  @all_buckets [:base, :standard, :pit]
  @no_pit [:base, :standard]

  defp buckets(requested, subscription, plan, interval \\ "month", trialing? \\ false) do
    AccessChecker.metric_version_buckets(requested, subscription, plan, interval, trialing?)
  end

  describe "SanAPI requests" do
    test "Sanbase subscriptions used on the API get version 1.0 only" do
      for plan <- ["PRO", "PRO_PLUS", "MAX"], interval <- ["month", "year"] do
        assert buckets("SANAPI", "SANBASE", plan, interval) == [:base], plan
      end
    end

    test "Business Pro gets the newer versions but not point-in-time" do
      for interval <- ["month", "year"] do
        assert buckets("SANAPI", "SANAPI", "BUSINESS_PRO", interval) == @no_pit
      end
    end

    test "Business Max monthly gets the newer versions but not point-in-time" do
      assert buckets("SANAPI", "SANAPI", "BUSINESS_MAX", "month") == @no_pit
    end

    test "Business Max yearly gets every version" do
      assert buckets("SANAPI", "SANAPI", "BUSINESS_MAX", "year") == @all_buckets
    end

    test "a Business Max yearly trial behaves like Business Max monthly" do
      assert buckets("SANAPI", "SANAPI", "BUSINESS_MAX", "year", true) == @no_pit
    end

    test "every other plan, and no subscription, gets version 1.0 only" do
      for plan <- ["FREE", "BASIC", "PRO", "PRO_PLUS", "INSTITUTIONAL", "ENTERPRISE", "CUSTOM"] do
        assert buckets("SANAPI", "SANAPI", plan, "year") == [:base], plan
      end

      assert buckets("SANAPI", nil, "FREE", nil) == [:base]
    end

    test "an unknown plan name falls back to version 1.0 instead of raising" do
      assert buckets("SANAPI", "SANAPI", "SOME_FUTURE_PLAN", "year") == [:base]
    end

    test "bundles resolve to their equivalent standard plan, PRO" do
      assert buckets("SANAPI", "SANAPI", "BUNDLE", "year") == [:base]
    end
  end

  describe "custom plans resolve through restricted_access_as_plan and their own interval" do
    setup context do
      Sanbase.Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 9101")
      {:ok, _} = create_custom_plan(context, 9100, "CUSTOM_VERSIONS_BMAX", "BUSINESS_MAX")
      {:ok, _} = create_custom_plan(context, 9200, "CUSTOM_VERSIONS_PRO", "PRO")
      :ok
    end

    test "based on Business Max, yearly" do
      assert buckets("SANAPI", "SANAPI", "CUSTOM_VERSIONS_BMAX", "year") == @all_buckets
    end

    test "based on Business Max, monthly" do
      assert buckets("SANAPI", "SANAPI", "CUSTOM_VERSIONS_BMAX", "month") == @no_pit
    end

    test "based on PRO" do
      assert buckets("SANAPI", "SANAPI", "CUSTOM_VERSIONS_PRO", "year") == [:base]
    end
  end

  test "Sanbase requests are never restricted" do
    for plan <- ["FREE", "PRO", "MAX", "BUSINESS_PRO", "BUSINESS_MAX", "BUNDLE"],
        subscription <- [nil, "SANBASE", "SANAPI"] do
      assert buckets("SANBASE", subscription, plan) == :all, plan
    end
  end

  defp create_custom_plan(context, id, name, base_plan) do
    Sanbase.Billing.Plan.create_custom_api_plan(%{
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
