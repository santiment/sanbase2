defmodule Sanbase.ApiCallLimit.SyncTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Repo
  alias Sanbase.ApiCallLimit
  alias Sanbase.ApiCallLimit.Sync

  setup do
    ApiCallLimit.ETS.clear_all()
    :ok
  end

  defp get_acl(user_id) do
    Repo.get_by(ApiCallLimit, user_id: user_id)
  end

  defp insert_acl(user, plan, status \\ "active") do
    now = DateTime.utc_now()
    month_str = now |> Timex.beginning_of_month() |> to_string()
    hour_str = %{now | minute: 0, second: 0, microsecond: {0, 0}} |> to_string()
    minute_str = %{now | second: 0, microsecond: {0, 0}} |> to_string()

    %ApiCallLimit{}
    |> ApiCallLimit.changeset(%{
      user_id: user.id,
      api_calls_limit_plan: plan,
      api_calls_limit_subscription_status: status,
      has_limits: plan != "sanapi_enterprise",
      api_calls: %{month_str => 0, hour_str => 0, minute_str => 0},
      api_calls_responses_size_mb: %{month_str => 0, hour_str => 0, minute_str => 0}
    })
    |> Repo.insert!()
  end

  defp insert_remote_ip_acl(ip) do
    now = DateTime.utc_now()
    month_str = now |> Timex.beginning_of_month() |> to_string()
    hour_str = %{now | minute: 0, second: 0, microsecond: {0, 0}} |> to_string()
    minute_str = %{now | second: 0, microsecond: {0, 0}} |> to_string()

    %ApiCallLimit{}
    |> ApiCallLimit.changeset(%{
      remote_ip: ip,
      api_calls_limit_plan: "sanapi_free",
      api_calls_limit_subscription_status: "active",
      has_limits: true,
      api_calls: %{month_str => 0, hour_str => 0, minute_str => 0},
      api_calls_responses_size_mb: %{month_str => 0, hour_str => 0, minute_str => 0}
    })
    |> Repo.insert!()
  end

  describe "run/0" do
    test "no-op when all ACL records are already correct", context do
      user = insert(:user, email: "correct@example.com")
      insert(:subscription_pro, user: user, plan: context.plans.plan_pro)
      insert_acl(user, "sanapi_pro")

      assert :ok = Sync.run()

      acl = get_acl(user.id)
      assert acl.api_calls_limit_plan == "sanapi_pro"
    end

    test "fixes stale paid ACL when subscription was canceled", _context do
      user = insert(:user, email: "stale@example.com")
      # ACL still says pro, but user has no active subscription
      insert_acl(user, "sanapi_pro")

      assert :ok = Sync.run()

      acl = get_acl(user.id)
      assert acl.api_calls_limit_plan == "sanapi_free"
    end

    test "fixes missing paid ACL when user has active subscription", context do
      user = insert(:user, email: "missing@example.com")
      insert(:subscription_pro, user: user, plan: context.plans.plan_pro)
      # ACL says free, but user has an active pro subscription
      insert_acl(user, "sanapi_free")

      assert :ok = Sync.run()

      acl = get_acl(user.id)
      assert acl.api_calls_limit_plan == "sanapi_pro"
    end

    test "fixes wrong plan when ACL has outdated plan name", context do
      user = insert(:user, email: "wrong@example.com")
      # User upgraded to business_pro, but ACL still says pro
      insert(:subscription_business_pro_monthly,
        user: user,
        plan: context.plans.plan_business_pro_monthly
      )

      insert_acl(user, "sanapi_pro")

      assert :ok = Sync.run()

      acl = get_acl(user.id)
      assert acl.api_calls_limit_plan == "sanapi_business_pro"
    end

    test "does not touch remote_ip ACL records", _context do
      insert_remote_ip_acl("1.2.3.4")
      insert_remote_ip_acl("5.6.7.8")

      assert :ok = Sync.run()

      # Remote IP records should remain unchanged
      assert Repo.get_by(ApiCallLimit, remote_ip: "1.2.3.4").api_calls_limit_plan == "sanapi_free"
      assert Repo.get_by(ApiCallLimit, remote_ip: "5.6.7.8").api_calls_limit_plan == "sanapi_free"
    end

    test "does not touch free users without subscriptions", _context do
      user = insert(:user, email: "freeuser@example.com")
      insert_acl(user, "sanapi_free")

      assert :ok = Sync.run()

      acl = get_acl(user.id)
      assert acl.api_calls_limit_plan == "sanapi_free"
    end

    test "handles sanbase product subscriptions", context do
      user = insert(:user, email: "sanbase@example.com")
      insert(:subscription_pro_sanbase, user: user, plan: context.plans.plan_pro_sanbase)
      insert_acl(user, "sanapi_free")

      assert :ok = Sync.run()

      acl = get_acl(user.id)
      assert acl.api_calls_limit_plan == "sanbase_pro"
    end

    test "API product subscription takes priority over Sanbase", context do
      user = insert(:user, email: "both@example.com")
      # User has both API and Sanbase subscriptions
      insert(:subscription_pro, user: user, plan: context.plans.plan_pro)
      insert(:subscription_pro_sanbase, user: user, plan: context.plans.plan_pro_sanbase)
      insert_acl(user, "sanbase_pro")

      assert :ok = Sync.run()

      acl = get_acl(user.id)
      # API product should win
      assert acl.api_calls_limit_plan == "sanapi_pro"
    end

    test "reconciles multiple users at once with mixed scenarios", context do
      # User 1: stale paid (no subscription)
      user_stale = insert(:user, email: "stale_multi@example.com")
      insert_acl(user_stale, "sanapi_pro")

      # User 2: missing paid (has subscription but ACL is free)
      user_missing = insert(:user, email: "missing_multi@example.com")
      insert(:subscription_pro, user: user_missing, plan: context.plans.plan_pro)
      insert_acl(user_missing, "sanapi_free")

      # User 3: wrong plan
      user_wrong = insert(:user, email: "wrong_multi@example.com")

      insert(:subscription_business_max_monthly,
        user: user_wrong,
        plan: context.plans.plan_business_max_monthly
      )

      insert_acl(user_wrong, "sanapi_pro")

      # User 4: correct (should not be touched)
      user_ok = insert(:user, email: "ok_multi@example.com")
      insert(:subscription_pro, user: user_ok, plan: context.plans.plan_pro)
      insert_acl(user_ok, "sanapi_pro")

      # User 5: free, no subscription (should not be touched)
      user_free = insert(:user, email: "free_multi@example.com")
      insert_acl(user_free, "sanapi_free")

      # Remote IP records (should be ignored)
      insert_remote_ip_acl("10.0.0.1")

      assert :ok = Sync.run()

      assert get_acl(user_stale.id).api_calls_limit_plan == "sanapi_free"
      assert get_acl(user_missing.id).api_calls_limit_plan == "sanapi_pro"
      assert get_acl(user_wrong.id).api_calls_limit_plan == "sanapi_business_max"
      assert get_acl(user_ok.id).api_calls_limit_plan == "sanapi_pro"
      assert get_acl(user_free.id).api_calls_limit_plan == "sanapi_free"
    end
  end

  describe "expected_plans_bulk/0" do
    test "ignores canceled subscriptions", context do
      user = insert(:user, email: "canceled@example.com")

      insert(:subscription_pro,
        user: user,
        plan: context.plans.plan_pro,
        status: "canceled"
      )

      expected = Sync.expected_plans_bulk()
      refute Map.has_key?(expected, user.id)
    end

    test "includes trialing subscriptions", context do
      user = insert(:user, email: "trialing@example.com")

      insert(:subscription_pro,
        user: user,
        plan: context.plans.plan_pro,
        status: "trialing"
      )

      expected = Sync.expected_plans_bulk()
      assert {plan, status} = expected[user.id]
      assert plan == "sanapi_pro"
      assert status == "trialing"
    end

    test "includes past_due subscriptions", context do
      user = insert(:user, email: "pastdue@example.com")

      insert(:subscription_pro,
        user: user,
        plan: context.plans.plan_pro,
        status: "past_due"
      )

      expected = Sync.expected_plans_bulk()
      assert {plan, status} = expected[user.id]
      assert plan == "sanapi_pro"
      assert status == "past_due"
    end
  end
end
