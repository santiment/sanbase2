defmodule Sanbase.Billing.Plan.Bundle.EntitlementTest do
  @moduledoc ~s"""
  The first working slice of the bundle path, checked from the database row all
  the way to the answer a request would get.

  What this proves:

    * an entitlement survives a round trip through the JSON column
    * access answers come from the entitlement, not from the plan ladder
    * two bundle subscriptions on the *same* plan name get *different* answers,
      which is the whole point of §5.8 and the thing a name-based lookup cannot do
    * a missing entitlement raises instead of quietly falling back

  It does **not** create anything in Stripe, does not use subscription items, and
  does not work the entitlement out from purchased packages. The entitlement is
  written by hand. That is deliberate: it validates the design before any of that
  machinery exists.
  """

  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Billing.Plan.AccessChecker
  alias Sanbase.Billing.Plan.Bundle
  alias Sanbase.Billing.Plan.Bundle.Entitlement
  alias Sanbase.Billing.Subscription
  alias Sanbase.Repo

  @bundle_plan_name "BUNDLE"

  # Market + Social, as a customer who bought those two packages would have.
  @market_and_social %{
    "packages" => ["market", "social"],
    "metric_access" => %{
      "accessible" => ["price_usd", "volume_usd"],
      "accessible_patterns" => ["^social_"],
      "not_accessible" => [],
      "not_accessible_patterns" => []
    },
    "query_access" => %{"accessible" => "all"},
    "signal_access" => %{"accessible" => "all"},
    "api_call_limits" => %{"month" => 100_000, "hour" => 30_000, "minute" => 600},
    "historical_data_in_days" => nil,
    "realtime_data_cut_off_in_days" => 0,
    "package_snapshot_version" => 1,
    "schema_version" => 1
  }

  # A different customer, on the same BUNDLE plan, who bought only Developer.
  @developer_only %{
    @market_and_social
    | "packages" => ["developer"],
      "metric_access" => %{"accessible" => ["dev_activity"]},
      "api_call_limits" => %{"month" => 600_000, "hour" => 30_000, "minute" => 600}
  }

  setup context do
    Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 9001")

    # amount: 0 because the real amounts live per item in the price catalog, not
    # on the plan row (§5.7).
    plan =
      insert(:plan_pro,
        id: 9200,
        name: @bundle_plan_name,
        product_id: context.product_api.id,
        amount: 0,
        stripe_id: "stripe_plan_" <> Ecto.UUID.generate()
      )

    %{plan: plan}
  end

  describe "the stored entitlement" do
    test "survives a round trip through the database", %{plan: plan} do
      subscription = create_bundle_subscription(plan, @market_and_social)

      %Subscription{bundle_entitlement: stored} = Repo.get!(Subscription, subscription.id)

      assert %Entitlement{} = stored
      assert stored.packages == ["market", "social"]
      assert stored.api_call_limits == %{"month" => 100_000, "hour" => 30_000, "minute" => 600}
      assert stored.historical_data_in_days == nil
      assert stored.realtime_data_cut_off_in_days == 0
      assert stored.schema_version == Entitlement.current_schema_version()
    end

    test "is nil for a subscription that is not a bundle", %{plan: plan} do
      user = insert(:user)
      subscription = insert(:subscription_pro, user_id: user.id, plan_id: plan.id)

      assert Repo.get!(Subscription, subscription.id).bundle_entitlement == nil
    end

    test "is rejected when the call limits are not ordered", %{plan: plan} do
      broken = %{
        @market_and_social
        | "api_call_limits" => %{"month" => 1, "hour" => 2, "minute" => 3}
      }

      assert {:error, changeset} = insert_bundle_subscription(plan, broken)

      assert "must be a map with integer month, hour and minute where month > hour > minute > 0" in errors_on(
               changeset
             ).bundle_entitlement.api_call_limits
    end

    test "is rejected when a pattern is not a valid regular expression", %{plan: plan} do
      # Stored unchecked, this raises Regex.CompileError inside every access check
      # instead of failing the one write that caused it.
      broken = %{
        @market_and_social
        | "metric_access" => %{"accessible" => [], "accessible_patterns" => ["^social_(", "*bad"]}
      }

      assert {:error, changeset} = insert_bundle_subscription(plan, broken)

      errors = errors_on(changeset).bundle_entitlement.metric_access

      assert Enum.any?(errors, &String.contains?(&1, "invalid regular expression"))
      assert length(errors) == 2
    end

    test "is rejected when an access list is not a list of strings", %{plan: plan} do
      broken = %{@market_and_social | "query_access" => %{"accessible" => [1, 2]}}

      assert {:error, changeset} = insert_bundle_subscription(plan, broken)

      assert ~s|"accessible" must be "all" or a list of strings| in errors_on(changeset).bundle_entitlement.query_access
    end

    test "is replaced wholesale, so a dropped package leaves nothing behind", %{plan: plan} do
      # A merge would let fields the new calculation omits keep their old values.
      subscription = create_bundle_subscription(plan, @market_and_social)

      {:ok, updated} =
        subscription
        |> Subscription.bundle_entitlement_changeset(@developer_only)
        |> Repo.update()

      stored = Repo.get!(Subscription, updated.id).bundle_entitlement

      assert stored.packages == ["developer"]
      assert stored.metric_access == %{"accessible" => ["dev_activity"]}
      refute Map.has_key?(stored.metric_access, "accessible_patterns")
    end

    test "can be cleared", %{plan: plan} do
      subscription = create_bundle_subscription(plan, @market_and_social)

      {:ok, updated} =
        subscription
        |> Subscription.bundle_entitlement_changeset(nil)
        |> Repo.update()

      assert Repo.get!(Subscription, updated.id).bundle_entitlement == nil
    end

    test "is not writable through the ordinary subscription changeset", %{plan: plan} do
      # An entitlement decides what a customer may use and how much. It is only
      # ever written by the code that works it out, never carried in alongside
      # ordinary attributes.
      subscription = create_bundle_subscription(plan, @market_and_social)

      {:ok, updated} =
        subscription
        |> Subscription.changeset(%{
          status: :past_due,
          bundle_entitlement: @developer_only
        })
        |> Repo.update()

      stored = Repo.get!(Subscription, updated.id)

      assert stored.status == :past_due
      assert stored.bundle_entitlement.packages == ["market", "social"]
    end

    test "detects data written by an older version" do
      current = %Entitlement{schema_version: Entitlement.current_schema_version()}
      older = %Entitlement{schema_version: 0}

      refute Entitlement.stale?(current)
      assert Entitlement.stale?(older)
      refute Entitlement.stale?(nil)
    end
  end

  describe "access comes from the entitlement" do
    setup %{plan: plan} do
      %{entitlement: create_bundle_subscription(plan, @market_and_social).bundle_entitlement}
    end

    test "a metric that was bought is allowed", %{entitlement: entitlement} do
      assert AccessChecker.plan_has_access?(
               {:metric, "price_usd"},
               "SANAPI",
               @bundle_plan_name,
               entitlement
             )
    end

    test "a metric matched by a pattern is allowed", %{entitlement: entitlement} do
      assert AccessChecker.plan_has_access?(
               {:metric, "social_volume_total"},
               "SANAPI",
               @bundle_plan_name,
               entitlement
             )
    end

    test "a metric that was not bought is refused", %{entitlement: entitlement} do
      refute AccessChecker.plan_has_access?(
               {:metric, "mvrv_usd"},
               "SANAPI",
               @bundle_plan_name,
               entitlement
             )
    end

    test "queries and signals are all allowed, matching today's behavior", %{
      entitlement: entitlement
    } do
      # §6.4 - queries and signals are effectively unrestricted, so bundles get
      # "all" rather than a per-package list.
      assert AccessChecker.plan_has_access?(
               {:query, :get_trending_words},
               "SANAPI",
               @bundle_plan_name,
               entitlement
             )

      assert AccessChecker.plan_has_access?(
               {:signal, "anomaly_eth_whale_dump"},
               "SANAPI",
               @bundle_plan_name,
               entitlement
             )
    end

    test "the answer is the same on both products", %{entitlement: entitlement} do
      for product <- ["SANAPI", "SANBASE"] do
        assert AccessChecker.plan_has_access?(
                 {:metric, "price_usd"},
                 product,
                 @bundle_plan_name,
                 entitlement
               )

        refute AccessChecker.plan_has_access?(
                 {:metric, "mvrv_usd"},
                 product,
                 @bundle_plan_name,
                 entitlement
               )
      end
    end
  end

  describe "two customers on the same plan name" do
    test "get different answers", %{plan: plan} do
      # This is the case a name-based lookup cannot handle, and the reason the
      # entitlement is passed in rather than looked up. Both subscriptions point
      # at the same BUNDLE plan row.
      market_social = create_bundle_subscription(plan, @market_and_social).bundle_entitlement
      developer = create_bundle_subscription(plan, @developer_only).bundle_entitlement

      assert AccessChecker.plan_has_access?(
               {:metric, "price_usd"},
               "SANAPI",
               @bundle_plan_name,
               market_social
             )

      refute AccessChecker.plan_has_access?(
               {:metric, "price_usd"},
               "SANAPI",
               @bundle_plan_name,
               developer
             )

      refute AccessChecker.plan_has_access?(
               {:metric, "dev_activity"},
               "SANAPI",
               @bundle_plan_name,
               market_social
             )

      assert AccessChecker.plan_has_access?(
               {:metric, "dev_activity"},
               "SANAPI",
               @bundle_plan_name,
               developer
             )

      assert Bundle.Access.api_call_limits(market_social).month == 100_000
      assert Bundle.Access.api_call_limits(developer).month == 600_000
    end
  end

  describe "quota" do
    test "comes from the entitlement, keyed the way the quota code expects", %{plan: plan} do
      entitlement = create_bundle_subscription(plan, @market_and_social).bundle_entitlement

      assert Bundle.Access.api_call_limits(entitlement) == %{
               month: 100_000,
               hour: 30_000,
               minute: 600
             }
    end

    test "a bundle always has limits" do
      # Answerable without an entitlement: there is no unlimited bundle.
      assert Sanbase.ApiCallLimit.plan_has_limits?("sanapi_bundle")
    end

    test "asking for limits by plan name still refuses, and says why" do
      # Every bundle is named BUNDLE, so the name cannot carry the numbers. The
      # error names the right place to look instead of returning something wrong.
      error =
        assert_raise Bundle.NotImplementedError, fn ->
          Sanbase.ApiCallLimit.plan_to_api_call_limits("sanapi_bundle")
        end

      assert error.message =~ "read_from_api_call_limits_row_instead"
    end
  end

  describe "a missing entitlement" do
    test "raises rather than falling back to the standard ladder" do
      # Falling back would answer from the ordinal plan ladder, which cannot
      # express packages, and would give a paying customer roughly free-tier
      # access with no error anywhere (§7.5 B1).
      error =
        assert_raise Bundle.MissingEntitlementError, fn ->
          AccessChecker.plan_has_access?({:metric, "price_usd"}, "SANAPI", @bundle_plan_name, nil)
        end

      assert error.message =~ "plan_has_access?"
      assert error.message =~ "no stored entitlement"
    end

    test "raises when the three-argument form is used for a bundle" do
      # The old signature cannot carry an entitlement, so it must fail rather
      # than silently answer.
      assert_raise Bundle.MissingEntitlementError, fn ->
        AccessChecker.plan_has_access?({:metric, "price_usd"}, "SANAPI", @bundle_plan_name)
      end
    end
  end

  defp create_bundle_subscription(plan, entitlement_attrs) do
    {:ok, subscription} = insert_bundle_subscription(plan, entitlement_attrs)
    subscription
  end

  defp insert_bundle_subscription(plan, entitlement_attrs) do
    user = insert(:user)

    subscription =
      insert(:subscription_pro,
        user_id: user.id,
        plan_id: plan.id,
        stripe_id: "sub_" <> Ecto.UUID.generate()
      )

    subscription
    |> Subscription.bundle_entitlement_changeset(entitlement_attrs)
    |> Repo.update()
  end
end
