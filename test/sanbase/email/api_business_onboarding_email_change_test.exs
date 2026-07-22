defmodule Sanbase.Email.ApiBusinessOnboardingEmailChangeTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import Mox

  alias Sanbase.Accounts.User
  alias Sanbase.Email.MockMailjetApi
  alias Sanbase.EventBus.UserEventsSubscriber

  setup :set_mox_global
  setup :verify_on_exit!

  @list :api_business_onboarding

  setup_all do
    Sanbase.EventBus.subscribe_subscriber(UserEventsSubscriber)

    on_exit(fn ->
      Sanbase.EventBus.drain_topics(UserEventsSubscriber.topics(), 10_000)
      Sanbase.EventBus.unsubscribe_subscriber(UserEventsSubscriber)
    end)
  end

  setup do
    Mox.allow(
      MockMailjetApi,
      self(),
      Process.whereis(UserEventsSubscriber)
    )

    :ok
  end

  test "eligible Business+ user changing email is added with the new address" do
    user = insert(:user, email: "old@example.com")
    insert(:subscription_business_pro_monthly, user: user)

    expect(MockMailjetApi, :subscribe, fn @list, "new@example.com" -> :ok end)

    assert {:ok, _} = User.Email.update_email(user, "new@example.com")

    :timer.sleep(100)
  end

  test "non-eligible user changing email is not added to the onboarding list" do
    user = insert(:user, email: "old@example.com")
    insert(:subscription_pro, user: user)

    assert {:ok, _} = User.Email.update_email(user, "new@example.com")

    :timer.sleep(100)
  end
end
