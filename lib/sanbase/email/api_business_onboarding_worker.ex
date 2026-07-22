defmodule Sanbase.Email.ApiBusinessOnboardingWorker do
  @moduledoc """
  Adds a subscriber to the API business onboarding Mailjet list.

  Enqueued by `Sanbase.EventBus.BillingEventSubscriber` on subscription
  create/update events so the Mailjet HTTP call runs off the billing GenServer
  and is retried by Oban on failure instead of being logged and dropped.

  Eligibility is re-checked here (not only at enqueue time) so a subscription that
  is no longer active by the time the job runs is not added.
  """
  use Oban.Worker, queue: :email_queue, max_attempts: 5

  alias Sanbase.Billing.Subscription
  alias Sanbase.Email.ApiBusinessOnboardingList

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"subscription_id" => subscription_id}}) do
    subscription_id
    |> Subscription.by_id()
    |> ApiBusinessOnboardingList.maybe_add()
  end
end
