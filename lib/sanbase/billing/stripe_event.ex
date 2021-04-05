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
  alias Sanbase.Accounts.User
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
  def create(%{"id" => id, "type" => type} = stripe_event) do
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

  def send_cancel_event_to_discord(subscription) do
    Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
      subscription = subscription |> Repo.preload([:user, plan: [:product]])
      created_months_ago = Timex.diff(Timex.now(), subscription.inserted_at, :months)

      duration =
        if created_months_ago == 0 do
          "#{Timex.diff(Timex.now(), subscription.inserted_at, :days)} days"
        else
          "#{created_months_ago} months"
        end

      message = """
      New cancellation scheduled for `#{subscription.current_period_end}` from `#{
        mask_user(subscription.user)
      }` for `#{Plan.plan_full_name(subscription.plan)}` | #{subscription.user.stripe_customer_id}.
      Subscription status before cancellation: `#{subscription.status}`.
      Subscription lasted #{duration}
      """

      if subscription.status == :active do
        do_send_to_discord(message, "Stripe Cancellation")
      end
    end)
  end

  defp handle_discord_notification(
         %{
           "type" => "invoice.payment_succeeded",
           "data" => %{"object" => %{"total" => total}}
         } = event
       )
       when total > 1 do
    message = build_payload(event)
    do_send_to_discord(message, "Stripe Payment")
  end

  defp handle_discord_notification(%{
         "id" => id,
         "type" => "charge.failed",
         "data" => %{"object" => %{"amount" => amount} = data}
       })
       when amount > 1 do
    message = """
    Failed card charge for #{format_cents_amount(amount)}.
    Details: #{data["failure_message"]}. #{get_in(data, ["outcome", "seller_message"]) || ""}
    Event: https://dashboard.stripe.com/events/#{id}
    """

    do_send_to_discord(message, "Stripe Payment")
  end

  defp handle_discord_notification(_), do: :ok

  defp do_send_to_discord(message, title) do
    payload = [message] |> Discord.encode!(publish_user())

    Discord.send_notification(webhook_url(), title, payload)
  end

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
    handle_subscription_created(
      id,
      "customer.subscription.created",
      subscription_id
    )
  end

  defp handle_event(%{
         "id" => _id,
         "type" => "customer.subscription.trial_will_end",
         "data" => %{"object" => %{"id" => subscription_id}}
       }) do
    Sanbase.Billing.Subscription.SignUpTrial.handle_trial_will_end(subscription_id)
  end

  defp handle_event(_), do: :ok

  defp handle_subscription_created(id, type, subscription_id) do
    with {:ok, stripe_subscription} <-
           StripeApi.retrieve_subscription(subscription_id),
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
    with {:ok, stripe_subscription} <-
           StripeApi.retrieve_subscription(subscription_id),
         {:nil?, %Subscription{} = subscription} <-
           {:nil?, Repo.get_by(Subscription, stripe_id: stripe_subscription.id)},
         {:ok, _subscription} <-
           Subscription.sync_subscription_with_stripe(
             stripe_subscription,
             subscription
           ) do
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

  defp build_payload(%{
         "data" => %{
           "object" => %{
             "total" => total,
             "starting_balance" => starting_balance,
             "subscription" => subscription
           }
         }
       })
       when is_binary(subscription) do
    Repo.get_by(Subscription, stripe_id: subscription)
    |> Repo.preload([:user, plan: [:product]])
    |> payload_for_subscription(total, starting_balance)
  end

  defp build_payload(%{
         "id" => id,
         "data" => %{
           "object" => %{
             "total" => total,
             "starting_balance" => starting_balance
           }
         }
       })
       when total == abs(starting_balance) do
    "New 🔥 for #{format_cents_amount(total)} received. Details: https://dashboard.stripe.com/events/#{
      id
    }"
  end

  defp build_payload(%{
         "id" => id,
         "data" => %{"object" => %{"total" => total}}
       }) do
    "New payment for #{format_cents_amount(total)} received. Details: https://dashboard.stripe.com/events/#{
      id
    }"
  end

  defp payload_for_subscription(
         %Subscription{
           plan: plan,
           user: user
         },
         total,
         starting_balance
       )
       when total == abs(starting_balance) do
    "New 🔥 for #{format_cents_amount(total)} for #{Plan.plan_full_name(plan)} by #{
      mask_user(user)
    }"
  end

  defp payload_for_subscription(
         %Subscription{
           plan: plan,
           inserted_at: inserted_at,
           user: user
         },
         total,
         _
       ) do
    calculate_recurring_month(inserted_at)
    |> case do
      1 ->
        "🎉 New payment for #{format_cents_amount(total)} for #{Plan.plan_full_name(plan)} by #{
          mask_user(user)
        }"

      count ->
        "Recurring payment for #{format_cents_amount(total)} for #{Plan.plan_full_name(plan)} (month #{
          count
        }) by #{mask_user(user)}"
    end
  end

  defp payload_for_subscription(_, total, starting_balance)
       when total == abs(starting_balance) do
    "New 🔥 for #{format_cents_amount(total)} received."
  end

  defp payload_for_subscription(_, total, _) do
    "New payment for #{format_cents_amount(total)} received."
  end

  defp mask_user(%User{email: email}) when is_binary(email) do
    [username, domain] = email |> String.split("@")

    masked_username =
      String.duplicate("*", String.length(username))
      |> String.replace_prefix("*", String.at(username, 0))
      |> String.replace_suffix("*", String.at(username, -1))

    "#{masked_username}@#{domain}"
  end

  defp mask_user(_) do
    "Metamask user"
  end

  # checks which month of recurring subscription it is by the subscription creation date
  defp calculate_recurring_month(inserted_at) do
    created_at_dt = inserted_at |> DateTime.from_naive!("Etc/UTC")
    Timex.diff(Timex.now(), created_at_dt, :months) + 1
  end

  defp format_cents_amount(amount) do
    "$" <> Number.Delimit.number_to_delimited(amount / 100, precision: 0)
  end

  defp webhook_url() do
    Config.get(:webhook_url)
  end

  defp publish_user() do
    Config.get(:publish_user)
  end
end
