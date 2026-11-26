defmodule Sanbase.Billing.Plan.PlanMetricAccessTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.Billing.Plan.PlanMetricAccess

  @metric "mvrv_usd"

  test "plans and channels are listed in display order" do
    assert Enum.map(PlanMetricAccess.plans(), & &1.key) ==
             ["free", "sanbase_pro", "sanbase_max", "business_pro", "business_max"]

    assert Enum.map(PlanMetricAccess.channels(), & &1.key) == [:sanbase, :api]

    assert %{label: "Business Pro", plan_name: "BUSINESS_PRO", subscription_product: "SANAPI"} =
             Enum.find(PlanMetricAccess.plans(), &(&1.key == "business_pro"))
  end

  test "headline windows match the checker modules" do
    assert PlanMetricAccess.headline("free", :sanbase) == {730, 30}
    assert PlanMetricAccess.headline("free", :api) == {365, 30}
    assert PlanMetricAccess.headline("sanbase_pro", :sanbase) == {nil, nil}
    assert PlanMetricAccess.headline("sanbase_pro", :api) == {365, 30}
    assert PlanMetricAccess.headline("sanbase_max", :api) == {730, nil}
    assert PlanMetricAccess.headline("business_pro", :sanbase) == {nil, nil}
    assert PlanMetricAccess.headline("business_pro", :api) == {730, nil}
    assert PlanMetricAccess.headline("business_max", :api) == {nil, nil}
  end

  test "a free metric is :free on every plan and channel" do
    metric = Sanbase.Metric.free_metrics() |> Enum.sort() |> hd()

    for %{key: plan} <- PlanMetricAccess.plans(),
        %{key: channel} <- PlanMetricAccess.channels() do
      assert PlanMetricAccess.access({:metric, metric}, plan, channel) == :free
    end
  end

  test "a restricted metric gets the plan window" do
    m = {:metric, @metric}
    assert PlanMetricAccess.access(m, "business_pro", :api) == {:window, 730, nil}
    assert PlanMetricAccess.access(m, "free", :api) == {:window, 365, 30}
    assert PlanMetricAccess.access(m, "free", :sanbase) == {:window, 730, 30}
    assert PlanMetricAccess.access(m, "business_max", :api) == {:window, nil, nil}
  end

  test "a max-only metric is locked below max, with the lowest unlocking plan" do
    # plan_has_access? reads the min plan through a local call, which meck cannot
    # intercept, so model a "max" min plan on both products directly.
    mock_plan_has_access(fn _query, product, plan_name ->
      Sanbase.Billing.Plan.StandardAccessChecker.max_plan?(product, plan_name)
    end)

    m = {:metric, @metric}

    assert PlanMetricAccess.access(m, "free", :sanbase) == {:locked, "sanbase_max"}
    assert PlanMetricAccess.access(m, "sanbase_pro", :sanbase) == {:locked, "sanbase_max"}
    assert PlanMetricAccess.access(m, "business_pro", :sanbase) == {:locked, "sanbase_max"}
    assert {:window, _, _} = PlanMetricAccess.access(m, "sanbase_max", :sanbase)
    assert PlanMetricAccess.access(m, "business_pro", :api) == {:locked, "business_max"}
    assert {:window, nil, nil} = PlanMetricAccess.access(m, "business_max", :api)
  end

  test "a metric no listed plan unlocks is {:locked, nil}" do
    mock_plan_has_access(fn _, _, _ -> false end)

    assert PlanMetricAccess.access({:metric, @metric}, "free", :api) == {:locked, nil}
    assert PlanMetricAccess.access({:metric, @metric}, "business_max", :sanbase) == {:locked, nil}
  end

  defp mock_plan_has_access(fun) do
    mod = Sanbase.Billing.Plan.AccessChecker
    :meck.new(mod, [:passthrough, :no_link])
    on_exit(fn -> :meck.unload(mod) end)
    :meck.expect(mod, :plan_has_access?, fun)
  end
end
