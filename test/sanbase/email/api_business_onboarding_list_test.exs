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
end
