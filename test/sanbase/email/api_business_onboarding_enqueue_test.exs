defmodule Sanbase.Email.ApiBusinessOnboardingEnqueueTest do
  use SanbaseWeb.ConnCase
  use Oban.Testing, repo: Sanbase.Repo

  import Sanbase.Factory

  alias Sanbase.Billing.Subscription
  alias Sanbase.Email.ApiBusinessOnboardingWorker

  setup_all do
    subscriber = Sanbase.EventBus.BillingEventSubscriber
    Sanbase.EventBus.subscribe_subscriber(subscriber)

    on_exit(fn ->
      Sanbase.EventBus.drain_topics(subscriber.topics(), 10_000)
      Sanbase.EventBus.unsubscribe_subscriber(subscriber)
    end)
  end

  test "a subscription create event enqueues a durable onboarding job" do
    user = insert(:user, email: "biz@example.com")

    {:ok, subscription} =
      Subscription.create(%{
        stripe_id: "sub_biz_#{user.id}",
        user_id: user.id,
        # plan_id 107 => API BUSINESS_PRO monthly (see test seed)
        plan_id: 107,
        status: "active"
      })

    # Process the emitted billing event synchronously while the shared sandbox
    # connection is still checked out, so the subscriber's Oban.insert lands.
    Sanbase.EventBus.drain_topics(["billing_events"], 10_000)

    assert_enqueued(
      worker: ApiBusinessOnboardingWorker,
      args: %{subscription_id: subscription.id}
    )
  end
end
