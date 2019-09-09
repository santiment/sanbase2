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

  alias Sanbase.Repo
  alias Sanbase.Auth.User
  alias Sanbase.Billing.{Subscription, Plan}
  alias Sanbase.StripeApi
  alias Sanbase.Notifications.Discord

  require Logger
  require Sanbase.Utils.Config, as: Config

  @primary_key false
  schema "stripe_events" do
    field(:event_id, :string, primary_key: true)
    field(:type, :string, null: false)
    field(:payload, :map, null: false)
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
  def create(
        %{
          "id" => id,
          "type" => type
        } = stripe_event
      ) do
    %__MODULE__{}
    |> changeset(%{event_id: id, type: type, payload: stripe_event})
    |> Repo.insert()
  end

  def update(id, params) do
    by_id(id)
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

    Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
      handle_discord_notification(stripe_event)
    end)
  end

  defp handle_discord_notification(%{
         "type" => "invoice.payment_succeeded",
         "data" => %{"object" => %{"total" => total}}
       })
       when total > 1 do
    payload =
      ["New payment for $#{total / 100} received"]
      |> Discord.encode!(publish_user())

    Discord.send_notification(
      webhook_url(),
      "Stripe Payment",
      payload
    )
  end

  defp handle_discord_notification(%{
         "id" => id,
         "type" => "charge.failed",
         "data" => %{"object" => %{"amount" => amount}}
       })
       when amount > 1 do
    payload =
      [
        "Failed card charge for $#{amount / 100} . Details: https://dashboard.stripe.com/events/${id}"
      ]
      |> Discord.encode!(publish_user())

    Discord.send_notification(
      webhook_url(),
      "Stripe Payment",
      payload
    )
  end

  defp handle_discord_notification(_), do: :ok

  defp handle_event(%{
         "id" => id,
         "type" => type,
         "data" => %{"object" => %{"subscription" => subscription_id}}
       })
       when type in [
              "invoice.payment_succeeded",
              "invoice.payment_failed"
            ] do
    handle_event_common(id, type, subscription_id)
  end

  # skip processing when payment is not connected to subscription
  defp handle_event(%{"id" => id, "type" => type})
       when type in ["invoice.payment_succeeded", "invoice.payment_failed"] do
    update(id, %{is_processed: true})
  end

  defp handle_event(%{
         "id" => id,
         "type" => type,
         "data" => %{"object" => %{"id" => subscription_id}}
       })
       when type in [
              "customer.subscription.updated",
              "customer.subscription.deleted"
            ] do
    handle_event_common(id, type, subscription_id)
  end

  defp handle_event(%{
         "id" => id,
         "type" => "customer.subscription.created",
         "data" => %{"object" => %{"id" => subscription_id}}
       }) do
    handle_subscription_created(id, "customer.subscription.created", subscription_id)
  end

  defp handle_event(_), do: :ok

  defp handle_subscription_created(id, type, subscription_id) do
    with {:ok, stripe_subscription} <- StripeApi.retrieve_subscription(subscription_id),
         {:user_nil?, %User{} = user} <-
           {:user_nil?, Repo.get_by(User, stripe_customer_id: stripe_subscription.customer)},
         {:plan_nil?, %Plan{} = plan} <-
           {:plan_nil?, Plan.by_stripe_id(stripe_subscription.plan.id)},
         {:ok, _subscription} <-
           Subscription.create_subscription_db(stripe_subscription, user, plan) do
      update(id, %{is_processed: true})
    else
      {:user_nil?, _} ->
        error_msg = "Customer for subscription_id #{subscription_id} does not exist"
        Logger.error(error_msg)
        {:error, error_msg}

      {:plan_nil?, _} ->
        error_msg = "Plan for subscription_id #{subscription_id} does not exist"
        Logger.error(error_msg)
        {:error, error_msg}

      {:error, reason} ->
        Logger.error("Error handling #{type} event: reason #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_event_common(id, type, subscription_id) do
    with {:ok, stripe_subscription} <- StripeApi.retrieve_subscription(subscription_id),
         {:nil?, %Subscription{} = subscription} <-
           {:nil?, Repo.get_by(Subscription, stripe_id: stripe_subscription.id)},
         {:ok, _subscription} <-
           Subscription.sync_with_stripe_subscription(stripe_subscription, subscription) do
      update(id, %{is_processed: true})
    else
      {:nil?, _} ->
        error_msg = "Subscription with stripe_id: #{subscription_id} does not exist"
        Logger.error(error_msg)
        {:error, error_msg}

      {:error, reason} ->
        Logger.error("Error handling #{type} event: reason #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp webhook_url() do
    Config.get(:webhook_url)
  end

  defp publish_user() do
    Config.get(:publish_user)
  end
end
