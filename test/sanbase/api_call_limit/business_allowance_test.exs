defmodule Sanbase.ApiCallLimit.BusinessAllowanceTest do
  @moduledoc ~s"""
  The reduced Business PRO / MAX monthly allowance for new subscriptions, and the
  grandfathering of everyone who subscribed before the cutoff.

  The cases that matter most are the ones where nothing should change: existing
  customers, rows nobody refreshed, and the feature toggle being off.
  """

  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory

  alias Sanbase.ApiCallLimit
  alias Sanbase.ApiCallLimit.BusinessAllowance
  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Subscription.Grants
  alias Sanbase.FeatureToggle
  alias Sanbase.Repo

  @cutoff ~N[2026-11-01 00:00:00]
  @created_before ~N[2026-10-15 12:00:00]
  @created_after ~N[2026-11-02 12:00:00]

  setup context do
    ApiCallLimit.ETS.clear_all()

    set_cutoff(@cutoff)

    %{
      user: insert(:user, email: "business#{System.unique_integer([:positive])}@example.com"),
      pro: context.plans.plan_business_pro_monthly,
      max: context.plans.plan_business_max_monthly
    }
  end

  describe "existing customers are not affected" do
    test "a Business PRO subscription from before the cutoff keeps 600,000", context do
      subscribe(context.user, context.pro, @created_before)

      assert limits(context.user) == %{month: 600_000, hour: 30_000, minute: 600}
      # Nothing is stored: the row keeps deriving its numbers from the plan name.
      assert acl(context.user).resolved_api_call_limits == nil
    end

    test "a Business MAX subscription from before the cutoff keeps 1,200,000", context do
      subscribe(context.user, context.max, @created_before)

      assert limits(context.user).month == 1_200_000
    end

    test "a row nobody refreshed after the deploy keeps the old allowance", context do
      # The row was written before the cutoff existed, then the cutoff was set and the
      # subscription turned out to be "new". Until something refreshes the row, the
      # customer must get the larger figure, never the smaller.
      set_cutoff(nil)
      subscribe(context.user, context.pro, @created_after)
      assert limits(context.user).month == 600_000

      set_cutoff(@cutoff)
      assert acl_limits(context.user).month == 600_000
    end

    test "the toggle off turns the reduction off", context do
      set_cutoff(nil)
      subscribe(context.user, context.pro, @created_after)

      assert limits(context.user).month == 600_000
      refute BusinessAllowance.active?()
    end

    test "non-Business plans are never reduced", context do
      subscribe(context.user, context.plans.plan_pro, @created_after)

      assert limits(context.user).month == 600_000
      assert acl(context.user).resolved_api_call_limits == nil
    end
  end

  describe "new subscriptions" do
    test "Business PRO from the cutoff on gets 50,000", context do
      subscribe(context.user, context.pro, @created_after)

      assert limits(context.user) == %{month: 50_000, hour: 30_000, minute: 600}
    end

    test "Business MAX from the cutoff on gets 50,000, bursts untouched", context do
      subscribe(context.user, context.max, @created_after)

      assert limits(context.user) == %{month: 50_000, hour: 60_000, minute: 1200}
    end

    test "a subscription created exactly at the cutoff is new", context do
      subscribe(context.user, context.pro, @cutoff)

      assert limits(context.user).month == 50_000
    end

    test "usage_and_limits reports the reduced figure", context do
      subscribe(context.user, context.pro, @created_after)

      assert {:ok, result} = ApiCallLimit.usage_and_limits(:user, context.user)
      assert result.plan == "sanapi_business_pro"
      assert result.api_calls_limits.month == 50_000
    end

    test "the quota path rate-limits at the reduced figure", context do
      subscribe(context.user, context.pro, @created_after)

      {:ok, _} = ApiCallLimit.get_quota_db(:user, context.user)
      {:ok, :updated} = ApiCallLimit.update_usage_db(:user, context.user, 50_000, 0)

      assert {:error, %{reason: :rate_limited}} = ApiCallLimit.get_quota_db(:user, context.user)
    end
  end

  describe "plan changes" do
    test "a grandfathered PRO customer upgrading to MAX on the same subscription stays grandfathered",
         context do
      subscription = subscribe(context.user, context.pro, @created_before)
      change_plan(subscription, context.max)

      assert limits(context.user).month == 1_200_000
    end

    test "a new customer upgrading PRO to MAX stays on the reduced allowance", context do
      subscription = subscribe(context.user, context.pro, @created_after)
      change_plan(subscription, context.max)

      assert limits(context.user) == %{month: 50_000, hour: 60_000, minute: 1200}
    end

    test "a reduced customer moving to a non-Business plan loses the marker", context do
      subscription = subscribe(context.user, context.pro, @created_after)
      change_plan(subscription, context.plans.plan_pro)

      assert acl(context.user).resolved_api_call_limits == nil
      assert limits(context.user).month == 600_000
    end

    test "a grandfathered customer who cancels and subscribes again is new", context do
      old = subscribe(context.user, context.pro, @created_before)
      old |> Ecto.Changeset.change(status: :canceled) |> Repo.update!()

      subscribe(context.user, context.pro, @created_after)

      assert limits(context.user).month == 50_000
    end
  end

  describe "grants on top" do
    test "add to the reduced allowance", context do
      subscription = subscribe(context.user, context.pro, @created_after)
      grant(subscription, context.user, 100_000)

      assert limits(context.user).month == 150_000
    end

    test "add to the grandfathered allowance", context do
      subscription = subscribe(context.user, context.pro, @created_before)
      grant(subscription, context.user, 100_000)

      assert limits(context.user).month == 700_000
    end

    test "removing the grant puts a reduced customer back on 50,000", context do
      subscription = subscribe(context.user, context.pro, @created_after)
      subscription = grant(subscription, context.user, 100_000)
      {:ok, _} = Grants.revoke(subscription)

      assert acl_limits(context.user).month == 50_000
    end
  end

  describe "plan catalog" do
    test "shows the reduced figure once the cutoff has passed", context do
      assert Plan.api_call_limits(context.pro).month == 50_000
      assert Plan.api_call_limits(context.max).month == 50_000
      assert Plan.api_call_limits(context.plans.plan_pro).month == 600_000
    end

    test "shows the old figure when the toggle is off", context do
      set_cutoff(nil)

      assert Plan.api_call_limits(context.pro).month == 600_000
    end
  end

  describe "the feature toggle" do
    test "is off by default, so nothing is reduced", context do
      Repo.delete_all(FeatureToggle)
      subscribe(context.user, context.pro, @created_after)

      assert BusinessAllowance.cutoff() == nil
      assert limits(context.user).month == 600_000
    end

    test "turning it on makes now the cutoff", context do
      set_cutoff(nil)
      before_enable = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      {:ok, _} = BusinessAllowance.enable()

      # Rounded up to the next whole second, never down: a cutoff before the moment
      # it was turned on would catch a subscription created just before it.
      cutoff = BusinessAllowance.cutoff()
      assert NaiveDateTime.compare(cutoff, before_enable) != :lt
      assert NaiveDateTime.diff(cutoff, before_enable) <= 2

      # Everyone who subscribed before it is grandfathered.
      subscribe(context.user, context.pro, @created_after)
      assert limits(context.user).month == 600_000
    end

    test "saving it on again does not move the cutoff" do
      set_cutoff(@cutoff)

      {:ok, _} = BusinessAllowance.enable()

      assert BusinessAllowance.cutoff() == @cutoff
    end

    test "turning it off puts reduced customers back on the old allowance at once",
         context do
      other = insert(:user, email: "business-other@example.com")
      subscribe(context.user, context.pro, @created_after)
      subscribe(other, context.max, @created_after)
      assert acl_limits(context.user).month == 50_000

      assert {:ok, _toggle, %{refreshed: 2, failed: []}} = BusinessAllowance.disable()

      assert BusinessAllowance.cutoff() == nil
      # Read without refreshing: the disable itself must have rewritten the rows.
      assert acl_limits(context.user).month == 600_000
      assert acl_limits(other).month == 1_200_000
      assert acl(context.user).resolved_api_call_limits == nil
    end

    test "a refresh that raises counts as that customer's failure, not the whole run",
         context do
      other = insert(:user, email: "business-raise@example.com")
      subscribe(context.user, context.pro, @created_after)
      subscribe(other, context.pro, @created_after)
      set_cutoff(nil)

      failing_id = other.id

      result =
        with_mock ApiCallLimit, [:passthrough],
          update_user_plan: fn
            %{id: ^failing_id} -> raise "boom"
            user -> passthrough([user])
          end do
          BusinessAllowance.refresh_reduced()
        end

      assert result == %{refreshed: 1, failed: [other.id]}
      assert acl_limits(context.user).month == 600_000
      assert acl_limits(other).month == 50_000
    end

    test "turning it off leaves grandfathered and granted rows alone", context do
      subscription = subscribe(context.user, context.pro, @created_before)
      grant(subscription, context.user, 100_000)

      assert {:ok, _toggle, %{refreshed: 0}} = BusinessAllowance.disable()
      assert acl_limits(context.user).month == 700_000
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────────

  defp subscribe(user, plan, inserted_at) do
    insert(:subscription_pro,
      user: user,
      plan_id: plan.id,
      status: :active,
      stripe_id: "sub_" <> Ecto.UUID.generate(),
      inserted_at: inserted_at
    )
    |> tap(fn _ -> {:ok, _} = ApiCallLimit.update_user_plan(user) end)
  end

  defp change_plan(subscription, plan) do
    subscription |> Ecto.Changeset.change(plan_id: plan.id) |> Repo.update!()

    {:ok, _} =
      ApiCallLimit.update_user_plan(Repo.get!(Sanbase.Accounts.User, subscription.user_id))
  end

  defp grant(subscription, user, calls) do
    subscription = Repo.preload(subscription, [:plan, :user])

    case Grants.grant(subscription, %{extra_api_calls_per_month: calls, note: "INV-1"}, user) do
      {:ok, subscription} -> subscription
    end
  end

  # Refreshes the row first, as every subscription event does.
  defp limits(user) do
    {:ok, _} = ApiCallLimit.update_user_plan(user)
    acl_limits(user)
  end

  # Reads the row as it stands, without refreshing it.
  defp acl_limits(user), do: user |> acl() |> ApiCallLimit.acl_to_api_call_limits()

  defp acl(user), do: Repo.get_by!(ApiCallLimit, user_id: user.id)

  # Writes the toggle row directly so a test can pick the cutoff; in production it is
  # always the moment the toggle was turned on.
  defp set_cutoff(nil), do: put_toggle(false, nil)

  defp set_cutoff(%NaiveDateTime{} = ndt),
    do: put_toggle(true, DateTime.from_naive!(ndt, "Etc/UTC"))

  defp put_toggle(enabled, enabled_at) do
    Repo.insert!(
      %FeatureToggle{
        name: FeatureToggle.business_reduced_api_calls_name(),
        enabled: enabled,
        enabled_at: enabled_at
      },
      on_conflict: {:replace, [:enabled, :enabled_at]},
      conflict_target: :name
    )
  end
end
