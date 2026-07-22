defmodule Sanbase.Email.ApiBusinessOnboardingWorkerTest do
  use Sanbase.DataCase, async: false
  use Oban.Testing, repo: Sanbase.Repo

  import Sanbase.Factory
  import Mox

  alias Sanbase.Email.ApiBusinessOnboardingWorker
  alias Sanbase.Email.MockMailjetApi

  setup :verify_on_exit!

  @list :api_business_onboarding

  test "adds an active business subscriber and returns :ok" do
    user = insert(:user, email: "biz@example.com")
    subscription = insert(:subscription_business_pro_monthly, user: user)

    expect(MockMailjetApi, :subscribe, fn @list, "biz@example.com" -> :ok end)

    assert :ok = perform_job(ApiBusinessOnboardingWorker, %{subscription_id: subscription.id})
  end

  test "does not add a non-eligible subscriber" do
    user = insert(:user, email: "user@example.com")
    subscription = insert(:subscription_pro_sanbase, user: user)

    # No Mox expectation is set, so any subscribe/2 call fails the test.
    assert :ok = perform_job(ApiBusinessOnboardingWorker, %{subscription_id: subscription.id})
  end

  test "propagates Mailjet errors so Oban retries the job" do
    user = insert(:user, email: "biz@example.com")
    subscription = insert(:subscription_business_max_monthly, user: user)

    expect(MockMailjetApi, :subscribe, fn @list, "biz@example.com" -> {:error, :timeout} end)

    assert {:error, :timeout} =
             perform_job(ApiBusinessOnboardingWorker, %{subscription_id: subscription.id})
  end

  test "is a no-op when the subscription no longer exists" do
    assert :ok = perform_job(ApiBusinessOnboardingWorker, %{subscription_id: 0})
  end
end
