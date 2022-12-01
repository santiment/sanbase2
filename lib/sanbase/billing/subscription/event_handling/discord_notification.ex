defmodule Sanbase.Billing.DiscordNotification do
  alias Sanbase.Accounts.User
  alias Sanbase.Notifications.Discord
  alias Sanbase.Billing.{Subscription, Plan, Product}

  alias Sanbase.Utils.Config

  def handle_event(
        :payment_success,
        %{
          data: %{
            total: total,
            extra_in_memory_data: %{stripe_event: stripe_event}
          }
        } = event
      )
      when total > 1 do
    build_payload(stripe_event, event)
    |> do_send_to_discord("Stripe Payment", webhook: "payments")
  end

  def handle_event(
        :charge_fail,
        %{
          data: %{
            amount: amount,
            stripe_event_id: stripe_event_id,
            extra_in_memory_data: %{stripe_event: stripe_event}
          }
        }
      )
      when amount > 1 do
    seller_message = stripe_event["data"]["object"]["outcome"]["seller_message"]
    failure_message = stripe_event["data"]["object"]["failure_message"]
    formatted_amount = format_cents_amount(amount)

    message = """
    ⛔ Failed card charge for #{formatted_amount}.
    Details: #{failure_message} #{seller_message}
    Event: https://dashboard.stripe.com/events/#{stripe_event_id}
    """

    do_send_to_discord(message, "Stripe Charge", webhook: "failed_payments")
  end

  def handle_event(
        :payment_action_required,
        %{
          data: %{
            amount: amount,
            stripe_event_id: stripe_event_id,
            extra_in_memory_data: %{stripe_event: stripe_event}
          }
        }
      )
      when amount > 1 do
    formatted_amount = format_cents_amount(amount)
    customer = stripe_event["data"]["object"]["customer"]
    customer = "https://dashboard.stripe.com/customers/#{customer}"

    message = """
    ⛔ A payment for #{formatted_amount} requires action.
    Customer: #{customer}
    Event: https://dashboard.stripe.com/events/#{stripe_event_id}
    """

    do_send_to_discord(message, "Stripe Payment", webhook: "payment-action-required")
  end

  def handle_event(:cancel_subscription, %{
        data: %{extra_in_memory_data: %{subscription: subscription}}
      }) do
    period_end = DateTime.truncate(subscription.current_period_end, :second)

    message = """
    😢 New cancellation scheduled for `#{period_end}` from \
    `#{mask_user(subscription.user)}` for \
    `#{Plan.plan_full_name(subscription.plan)}` | #{subscription.user.stripe_customer_id}.
    Subscription status before cancellation: `#{subscription.status}`.
    Subscription time left: #{subscription_time_left_str(subscription)}
    Subscription lasted: #{subscription_duration_lasted_str(subscription)}
    """

    if subscription.status == :active do
      do_send_to_discord(message, "Stripe Cancellation", webhook: "failed_payments")

      if subscription.plan.product_id == Product.product_sanbase() do
        Sanbase.Accounts.EmailJobs.send_post_cancellation_email(subscription)
      end
    end
  end

  def handle_event(_event_type, _event) do
    :ok
  end

  defp subscription_time_left_str(subscription) do
    days_left = abs(Timex.diff(subscription.current_period_end, Timex.now(), :days))
    hours_left = abs(Timex.diff(subscription.current_period_end, Timex.now(), :hours))

    cond do
      days_left == 0 and hours_left == 1 -> "1 hour"
      days_left == 0 -> "#{hours_left} hours"
      days_left == 1 -> "1 day"
      true -> "#{days_left} days"
    end
  end

  defp subscription_duration_lasted_str(subscription) do
    created_months_ago = Timex.diff(Timex.now(), subscription.inserted_at, :months)

    case created_months_ago do
      0 -> "#{Timex.diff(Timex.now(), subscription.inserted_at, :days)} days"
      1 -> "#{created_months_ago} month"
      _ -> "#{created_months_ago} months"
    end
  end

  defp do_send_to_discord(message, title, opts) do
    payload = [message] |> Discord.encode!(publish_user())

    webhook_url =
      case Keyword.get(opts, :webhook, "payments") do
        "payments" -> payments_webhook_url()
        "failed_payments" -> failed_payments_webhook_url()
        "payment-action-required" -> payment_action_required_webhook_url()
      end

    Discord.send_notification(webhook_url, title, payload)
  end

  defp build_payload(
         %{
           "data" => %{
             "object" => %{
               "total" => total,
               "starting_balance" => starting_balance,
               "subscription" => stripe_subscription_id
             }
           }
         },
         event
       )
       when is_binary(stripe_subscription_id) do
    Subscription.by_stripe_id(stripe_subscription_id)
    |> payload_for_subscription(total, starting_balance, event)
  end

  defp build_payload(
         %{
           "id" => id,
           "data" => %{
             "object" => %{
               "total" => total,
               "starting_balance" => starting_balance
             }
           }
         },
         event
       )
       when total == abs(starting_balance) do
    """
    🎉 New 🔥 for #{format_cents_amount(total)} received. \
    Details: https://dashboard.stripe.com/events/#{id}
    """ <> payment_details(event)
  end

  defp build_payload(
         %{
           "id" => id,
           "data" => %{"object" => %{"total" => total}}
         },
         event
       ) do
    """
    🎉 New payment for #{format_cents_amount(total)} received.
    Details: https://dashboard.stripe.com/events/#{id}
    """ <> payment_details(event)
  end

  defp payload_for_subscription(
         %Subscription{plan: plan, user: user},
         total,
         starting_balance,
         event
       )
       when total == abs(starting_balance) do
    """
    New 🔥 for #{format_cents_amount(total)} for #{Plan.plan_full_name(plan)} \
    by #{mask_user(user)}
    """ <> payment_details(event)
  end

  defp payload_for_subscription(
         %Subscription{plan: plan, inserted_at: inserted_at, user: user},
         total,
         _starting_balance,
         event
       ) do
    case calculate_recurring_month(inserted_at) do
      1 ->
        """
        🎉 New payment for #{format_cents_amount(total)} for \
        #{Plan.plan_full_name(plan)} by #{mask_user(user)}
        """ <> payment_details(event)

      count ->
        """
        ⏰ Recurring payment for #{format_cents_amount(total)} for \
        #{Plan.plan_full_name(plan)} (month #{count}) by #{mask_user(user)}
        """ <> payment_details(event)
    end
  end

  defp payload_for_subscription(_subscription, total, starting_balance, event)
       when total == abs(starting_balance) do
    """
    🎉 New 🔥 for #{format_cents_amount(total)} received.
    """ <> payment_details(event)
  end

  defp payload_for_subscription(_subscription, total, _starting_balance, event) do
    """
    🎉 New payment for #{format_cents_amount(total)} received.
    """ <> payment_details(event)
  end

  defp payment_details(%{data: data}) do
    [
      data.coupon_name && "Coupon name: #{data.coupon_name}",
      data.coupon_id && "Coupon id: #{data.coupon_id}",
      data.coupon_percent_off && "Coupon percent off: #{data.coupon_percent_off}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
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

  defp payments_webhook_url(),
    do: Config.module_get(__MODULE__, :payments_webhook_url)

  defp failed_payments_webhook_url(),
    do: Config.module_get(__MODULE__, :failed_payments_webhook_url)

  defp payment_action_required_webhook_url(),
    do:
      Config.module_get(__MODULE__, :payment_action_required_webhook_url) ||
        failed_payments_webhook_url()

  defp publish_user(),
    do: Config.module_get(__MODULE__, :publish_user)
end
