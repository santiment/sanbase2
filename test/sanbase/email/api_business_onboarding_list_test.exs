defmodule Sanbase.Email.ApiBusinessOnboardingListTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import Mox

  alias Sanbase.Billing.Subscription
  alias Sanbase.Email.ApiBusinessOnboardingList
  alias Sanbase.Email.MockMailjetApi

  setup :verify_on_exit!

  @list :api_business_onboarding

  defp reload(subscription), do: Subscription.by_id(subscription.id)

  describe "maybe_add/1 adds eligible subscribers" do
    setup do
      {:ok, user: insert(:user, email: "biz@example.com")}
    end

    test "active BUSINESS_PRO subscriber is added to the list", %{user: user} do
      subscription = insert(:subscription_business_pro_monthly, user: user) |> reload()

      expect(MockMailjetApi, :subscribe, fn @list, "biz@example.com" -> :ok end)

      assert :ok = ApiBusinessOnboardingList.maybe_add(subscription)
    end

    test "active BUSINESS_MAX subscriber is added to the list", %{user: user} do
      subscription = insert(:subscription_business_max_monthly, user: user) |> reload()

      expect(MockMailjetApi, :subscribe, fn @list, "biz@example.com" -> :ok end)

      assert :ok = ApiBusinessOnboardingList.maybe_add(subscription)
    end

    test "active CUSTOM (enterprise) API subscriber is added to the list", %{user: user} do
      subscription = insert(:subscription_custom, user: user) |> reload()

      expect(MockMailjetApi, :subscribe, fn @list, "biz@example.com" -> :ok end)

      assert :ok = ApiBusinessOnboardingList.maybe_add(subscription)
    end
  end

  describe "maybe_add/1 ignores non-eligible subscribers" do
    # No Mox expectation is set in these tests, so any call to subscribe/2 raises
    # Mox.UnexpectedCallError and fails the test - exactly what we want to assert.
    setup do
      {:ok, user: insert(:user, email: "user@example.com")}
    end

    test "Sanbase PRO subscriber is not added", %{user: user} do
      subscription = insert(:subscription_pro_sanbase, user: user) |> reload()
      assert :ok = ApiBusinessOnboardingList.maybe_add(subscription)
    end

    test "API PRO (below Business) subscriber is not added", %{user: user} do
      subscription = insert(:subscription_pro, user: user) |> reload()
      assert :ok = ApiBusinessOnboardingList.maybe_add(subscription)
    end

    test "inactive (incomplete) BUSINESS_PRO subscription is not added", %{user: user} do
      subscription =
        insert(:subscription_business_pro_monthly, user: user, status: :incomplete) |> reload()

      assert :ok = ApiBusinessOnboardingList.maybe_add(subscription)
    end

    test "BUSINESS_PRO subscriber without an email is not added" do
      user = insert(:user, email: nil)
      subscription = insert(:subscription_business_pro_monthly, user: user) |> reload()
      assert :ok = ApiBusinessOnboardingList.maybe_add(subscription)
    end

    test "nil subscription is a no-op" do
      assert :ok = ApiBusinessOnboardingList.maybe_add(nil)
    end
  end

  describe "eligible?/1" do
    setup do
      {:ok, user: insert(:user, email: "biz@example.com")}
    end

    test "true for active Business-or-higher API plans", %{user: user} do
      for factory <- [
            :subscription_business_pro_monthly,
            :subscription_business_max_monthly,
            :subscription_custom
          ] do
        subscription = insert(factory, user: user) |> reload()
        assert ApiBusinessOnboardingList.eligible?(subscription)
      end
    end

    test "false for Sanbase PRO", %{user: user} do
      subscription = insert(:subscription_pro_sanbase, user: user) |> reload()
      refute ApiBusinessOnboardingList.eligible?(subscription)
    end

    test "false for an inactive Business plan", %{user: user} do
      subscription =
        insert(:subscription_business_pro_monthly, user: user, status: :incomplete) |> reload()

      refute ApiBusinessOnboardingList.eligible?(subscription)
    end

    test "false for nil" do
      refute ApiBusinessOnboardingList.eligible?(nil)
    end
  end

  describe "maybe_add_user/1" do
    @since ~N[2025-01-01 00:00:00]

    setup do
      previous = Application.get_env(:sanbase, ApiBusinessOnboardingList, [])

      Application.put_env(
        :sanbase,
        ApiBusinessOnboardingList,
        Keyword.put(previous, :api_business_onboarding_since, @since)
      )

      on_exit(fn ->
        Application.put_env(:sanbase, ApiBusinessOnboardingList, previous)
      end)

      :ok
    end

    test "adds the current email when the user has an eligible post-cutoff subscription" do
      user = insert(:user, email: "new@example.com")
      insert(:subscription_business_pro_monthly, user: user)

      expect(MockMailjetApi, :subscribe, fn @list, "new@example.com" -> :ok end)

      assert :ok = ApiBusinessOnboardingList.maybe_add_user(user.id)
    end

    test "does not subscribe when the user has no eligible subscription" do
      user = insert(:user, email: "user@example.com")
      insert(:subscription_pro, user: user)

      assert :ok = ApiBusinessOnboardingList.maybe_add_user(user.id)
    end

    test "does not subscribe when the eligible subscription is pre-cutoff" do
      user = insert(:user, email: "historical@example.com")
      sub = insert(:subscription_business_pro_monthly, user: user)

      sub
      |> Ecto.Changeset.change(%{inserted_at: ~N[2020-01-01 00:00:00]})
      |> Sanbase.Repo.update!()

      assert :ok = ApiBusinessOnboardingList.maybe_add_user(user.id)
    end
  end

  describe "reconcile/0" do
    @since ~N[2025-01-01 00:00:00]

    setup do
      previous = Application.get_env(:sanbase, ApiBusinessOnboardingList, [])

      Application.put_env(
        :sanbase,
        ApiBusinessOnboardingList,
        Keyword.put(previous, :api_business_onboarding_since, @since)
      )

      on_exit(fn ->
        Application.put_env(:sanbase, ApiBusinessOnboardingList, previous)
      end)

      :ok
    end

    test "adds only missing post-cutoff eligible emails and reports extras" do
      missing_user = insert(:user, email: "missing@example.com")
      present_user = insert(:user, email: "present@example.com")
      old_user = insert(:user, email: "historical@example.com")

      insert(:subscription_business_pro_monthly, user: missing_user)
      insert(:subscription_business_pro_monthly, user: present_user)

      old_sub = insert(:subscription_business_pro_monthly, user: old_user)

      old_sub
      |> Ecto.Changeset.change(%{inserted_at: ~N[2020-01-01 00:00:00]})
      |> Sanbase.Repo.update!()

      expect(MockMailjetApi, :fetch_list_emails, fn @list ->
        {:ok, ["present@example.com", "stale@example.com"]}
      end)

      expect(MockMailjetApi, :subscribe, fn @list, emails ->
        assert Enum.sort(List.wrap(emails)) == ["missing@example.com"]
        :ok
      end)

      assert %{
               added: 1,
               missing_emails: ["missing@example.com"],
               extra_count: 1
             } = ApiBusinessOnboardingList.reconcile()
    end

    test "is idempotent when Mailjet already has all desired members" do
      user = insert(:user, email: "present@example.com")
      insert(:subscription_business_pro_monthly, user: user)

      expect(MockMailjetApi, :fetch_list_emails, fn @list ->
        {:ok, ["present@example.com"]}
      end)

      assert %{added: 0, missing_emails: [], extra_count: 0} =
               ApiBusinessOnboardingList.reconcile()
    end

    test "skips adds when the launch cutoff is not configured" do
      Application.put_env(:sanbase, ApiBusinessOnboardingList, [])

      user = insert(:user, email: "biz@example.com")
      insert(:subscription_business_pro_monthly, user: user)

      assert %{added: 0, missing_emails: [], extra_count: 0} =
               ApiBusinessOnboardingList.reconcile()
    end

    test "does not include pre-cutoff eligible subscriptions in desired emails" do
      user = insert(:user, email: "historical@example.com")
      sub = insert(:subscription_business_pro_monthly, user: user)

      sub
      |> Ecto.Changeset.change(%{inserted_at: ~N[2020-01-01 00:00:00]})
      |> Sanbase.Repo.update!()

      assert ApiBusinessOnboardingList.eligible_user_emails() == []
    end
  end
end
