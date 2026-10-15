defmodule Sanbase.Billing.Plan.MinPlanMaxTest do
  @moduledoc ~s"""
  A metric with min plan `max` is accessible only by the top tier of each
  product: Sanbase MAX on Sanbase, and BUSINESS_MAX and above on SanAPI (which
  has no MAX plan).
  """
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Billing.Plan.AccessChecker

  @metric "stock_to_flow"

  setup do
    {:ok, registry} = Sanbase.Metric.Registry.by_name(@metric)
    original = Map.take(registry, [:sanapi_min_plan, :sanbase_min_plan])

    {:ok, _} =
      Sanbase.Metric.Registry.update(registry, %{sanapi_min_plan: "max", sanbase_min_plan: "max"},
        emit_event: false
      )

    Sanbase.Metric.Registry.refresh_stored_terms()

    %{original: original}
  end

  test "SanAPI: only BUSINESS_MAX and above have access", context do
    with_restored_registry(context, fn ->
      for plan <- ["BUSINESS_MAX", "INSTITUTIONAL", "ENTERPRISE", "CUSTOM", "PREMIUM"] do
        assert AccessChecker.plan_has_access?({:metric, @metric}, "SANAPI", plan), plan
      end

      for plan <- ["FREE", "BASIC", "PRO", "PRO_PLUS", "MAX", "BUSINESS_PRO"] do
        refute AccessChecker.plan_has_access?({:metric, @metric}, "SANAPI", plan), plan
      end
    end)
  end

  test "Sanbase: only MAX has access", context do
    with_restored_registry(context, fn ->
      assert AccessChecker.plan_has_access?({:metric, @metric}, "SANBASE", "MAX")

      for plan <- [
            "FREE",
            "BASIC",
            "PRO",
            "PRO_PLUS",
            "BUSINESS_PRO",
            "BUSINESS_MAX",
            "INSTITUTIONAL",
            "ENTERPRISE",
            "CUSTOM",
            "PREMIUM"
          ] do
        refute AccessChecker.plan_has_access?({:metric, @metric}, "SANBASE", plan), plan
      end
    end)
  end

  test "the SanAPI access error suggests an existing plan", context do
    with_restored_registry(context, fn ->
      insert(:project, slug: "bitcoin")
      %{user: user} = insert(:subscription_business_pro_monthly, user: insert(:user))
      {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(user)

      to = DateTime.utc_now()
      from = DateTime.add(to, -2, :day)

      query = """
      {
        getMetric(metric: "#{@metric}") {
          timeseriesData(slug: "bitcoin", from: "#{from}", to: "#{to}", interval: "1d") {
            datetime
            value
          }
        }
      }
      """

      result =
        build_conn()
        |> setup_apikey_auth(apikey)
        |> post("/graphql", query_skeleton(query))
        |> json_response(200)

      assert [%{"message" => message}] = result["errors"]
      assert message =~ "Please upgrade to SANAPI BUSINESS_MAX subscription"
    end)
  end

  describe "custom plans" do
    setup context do
      Sanbase.Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 9401")
      {:ok, _} = create_custom_plan(context, 9300, "CUSTOM_MAX_TEST_BMAX", "BUSINESS_MAX", "all")
      {:ok, _} = create_custom_plan(context, 9301, "CUSTOM_MAX_TEST_PRO", "PRO", "all")

      {:ok, _} =
        create_custom_plan(context, 9302, "CUSTOM_MAX_TEST_BMAX_LIST", "BUSINESS_MAX", [])

      :ok
    end

    test "need the metric in the allow-list and restricted_access_as_plan BUSINESS_MAX",
         context do
      with_restored_registry(context, fn ->
        assert AccessChecker.plan_has_access?(
                 {:metric, @metric},
                 "SANAPI",
                 "CUSTOM_MAX_TEST_BMAX"
               )

        refute AccessChecker.plan_has_access?({:metric, @metric}, "SANAPI", "CUSTOM_MAX_TEST_PRO")

        refute AccessChecker.plan_has_access?(
                 {:metric, @metric},
                 "SANAPI",
                 "CUSTOM_MAX_TEST_BMAX_LIST"
               )

        # Metrics below "max" are still decided by the allow-list alone
        assert AccessChecker.plan_has_access?(
                 {:metric, "price_usd"},
                 "SANAPI",
                 "CUSTOM_MAX_TEST_PRO"
               )

        assert @metric in available_metrics("CUSTOM_MAX_TEST_BMAX")
        refute @metric in available_metrics("CUSTOM_MAX_TEST_PRO")
        assert "price_usd" in available_metrics("CUSTOM_MAX_TEST_PRO")
      end)
    end
  end

  defp available_metrics(plan_name),
    do: AccessChecker.get_available_metrics_for_plan(plan_name, "SANAPI", :all)

  defp create_custom_plan(context, id, name, restricted_access_as_plan, accessible_metrics) do
    Sanbase.Billing.Plan.create_custom_api_plan(%{
      id: id,
      name: name,
      product_id: context.product_api.id,
      stripe_id: context.product_api.stripe_id,
      restrictions: %{
        restricted_access_as_plan: restricted_access_as_plan,
        api_call_limits: %{"minute" => 1000, "hour" => 100_000, "month" => 3_000_000},
        historical_data_in_days: 365,
        realtime_data_cut_off_in_days: 0,
        metric_access: %{"accessible" => accessible_metrics, "not_accessible" => []},
        query_access: %{"accessible" => "all", "not_accessible" => []},
        signal_access: %{"accessible" => "all", "not_accessible" => []}
      },
      amount: 35_900,
      currency: "USD",
      interval: "year"
    })
  end

  # The registry is kept in persistent_term, which the DB sandbox rollback does not
  # undo, so it is restored while the test process still has DB access.
  defp with_restored_registry(context, fun) do
    fun.()
  after
    {:ok, registry} = Sanbase.Metric.Registry.by_name(@metric)
    {:ok, _} = Sanbase.Metric.Registry.update(registry, context.original, emit_event: false)
    Sanbase.Metric.Registry.refresh_stored_terms()
  end
end
