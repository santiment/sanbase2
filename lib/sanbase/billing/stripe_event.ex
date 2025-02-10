defmodule Sanbase.Billing.StripeEvent do
  @moduledoc """
  Module for persisting and handling Stripe webhook events.

  Events are persisted for 3 reasons:
  1. Help making event processing idempotent by not processing already processed events
  (https://stripe.com/docs/webhooks/best-practices#duplicate-events)
  2. Replay event if something happens.
  3. Have a log of received events - that will help for fixing bugs.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Sanbase.Billing.EventEmitter, only: [emit_event: 3]

  alias Sanbase.Accounts.User
  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Subscription
  alias Sanbase.Repo
  alias Sanbase.StripeApi

  require Logger

  @primary_key false
  schema "stripe_events" do
    field(:event_id, :string, primary_key: true)
    field(:type, :string)
    field(:payload, :map)
    field(:is_processed, :boolean, default: false)

    timestamps()
  end

  def changeset(%__MODULE__{} = stripe_event, attrs \\ %{}) do
    stripe_event
    |> cast(attrs, [:event_id, :type, :payload, :is_processed])
    |> validate_required([:event_id, :type, :payload, :is_processed])
  end

  def by_id(event_id) do
    Repo.get(__MODULE__, event_id)
  end

  @doc """
  Log event details with initial status `is_processed: false`
  """
  def create(%{"id" => id, "type" => type} = stripe_event) do
    %__MODULE__{}
    |> changeset(%{event_id: id, type: type, payload: stripe_event})
    |> Repo.insert()
  end

  def update(id, params) do
    id
    |> by_id()
    |> changeset(params)
    |> Repo.update()
  end

  @doc """
  Handle different types of events asyncroniously.

  Every event type has different logic for handling.
  After handling is done - updating the event in processed status.
  """
  def handle_event_async(stripe_event) do
    Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
      handle_event(stripe_event)
    end)
  end

  defp to_event_type("invoice.payment_succeeded"), do: :payment_success
  defp to_event_type("invoice.payment_failed"), do: :payment_fail
  defp to_event_type("charge.failed"), do: :charge_fail
  defp to_event_type("invoice.payment_action_required"), do: :payment_action_required

  defp handle_event(
         %{"id" => id, "type" => type, "data" => %{"object" => %{"subscription" => subscription_id}}} = stripe_event
       )
       when type in ["invoice.payment_succeeded", "invoice.payment_failed"] do
    emit_event({:ok, stripe_event}, to_event_type(type), %{})
    handle_event_common(id, type, subscription_id)
  end

  defp handle_event(%{
         "id" => id,
         "type" => "invoice.upcoming",
         "data" => %{
           "object" => %{
             "subscription" => subscription_id,
             "next_payment_attempt" => charge_date,
             "amount_due" => amount_due
           }
         }
       }) do
    if amount_due > 0 do
      subscription = Subscription.by_stripe_id(subscription_id)
      # only active Sanbase subscriptions
      if subscription.status == :active and subscription.plan.product_id == 2 do
        Sanbase.Accounts.EmailJobs.send_automatic_renewal_email(subscription, charge_date)
      end
    end

    update(id, %{is_processed: true})
  end

  defp handle_event(%{"id" => id, "type" => type} = stripe_event)
       when type in ["invoice.payment_action_required", "charge.failed"] do
    emit_event({:ok, stripe_event}, to_event_type(type), %{})

    update(id, %{is_processed: true})
  end

  # skip processing when payment is not connected to subscription
  defp handle_event(%{"id" => id, "type" => type}) when type in ["invoice.payment_succeeded", "invoice.payment_failed"] do
    update(id, %{is_processed: true})
  end

  defp handle_event(%{"id" => id, "type" => type, "data" => %{"object" => %{"id" => subscription_id}}})
       when type in ["customer.subscription.updated", "customer.subscription.deleted"] do
    handle_event_common(id, type, subscription_id)
  end

  defp handle_event(%{
         "id" => id,
         "type" => "customer.subscription.created",
         "data" => %{"object" => %{"id" => subscription_id}}
       }) do
    handle_subscription_created(
      id,
      "customer.subscription.created",
      subscription_id
    )
  end

  defp handle_event(_), do: :ok

  defp handle_subscription_created(id, type, subscription_id) do
    with {:ok, stripe_sub} <-
           StripeApi.retrieve_subscription(subscription_id),
         {_, {:ok, %User{} = user}} <- {:user?, User.by_stripe_customer_id(stripe_sub.customer)},
         stripe_plan_id = stripe_sub.items.data |> hd() |> Map.get(:plan) |> Map.get(:id),
         {_, %Plan{} = plan} <- {:plan?, Plan.by_stripe_id(stripe_plan_id)},
         {:ok, _sub} <- Subscription.create_subscription_db(stripe_sub, user, plan) do
      update(id, %{is_processed: true})
    else
      {:user?, _} ->
        error_msg = "Customer for subscription_id #{subscription_id} does not exist"
        Logger.error(error_msg)
        {:error, error_msg}

      {:plan?, _} ->
        error_msg = "Plan for subscription_id #{subscription_id} does not exist"
        Logger.error(error_msg)
        {:error, error_msg}

      {:error, reason} ->
        Logger.error("Error handling #{type} event. Reason: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_event_common(id, type, subscription_id) do
    with {:ok, stripe_sub} <- StripeApi.retrieve_subscription(subscription_id),
         {_, %Subscription{} = subscription} <- {:sub?, Subscription.by_stripe_id(stripe_sub.id)},
         {:ok, _subscription} <-
           Subscription.sync_subscription_with_stripe(stripe_sub, subscription) do
      update(id, %{is_processed: true})
    else
      {:sub?, _} ->
        error_msg = "Subscription with stripe_id: #{subscription_id} does not exist"

        Logger.error(error_msg)
        {:error, error_msg}

      {:error, reason} ->
        Logger.error("Error handling #{type} event. Reason: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
