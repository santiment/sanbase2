defmodule SanbaseWeb.Graphql.Resolvers.BillingResolver do
  alias Sanbase.Billing
  alias Sanbase.Billing.{Subscription, Plan}
  alias Sanbase.Accounts.User

  alias Sanbase.StripeApi

  require Logger

  def products_with_plans(_root, _args, _resolution) do
    Plan.product_with_plans()
  end

  def subscribe(_root, %{plan_id: plan_id} = args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    card_token = Map.get(args, :card_token)
    coupon = Map.get(args, :coupon)

    with {:plan?, %Plan{is_deprecated: false} = plan} <- {:plan?, Plan.by_id(plan_id)},
         {:ok, subscription} <- Billing.subscribe(current_user, plan, card_token, coupon) do
      {:ok, subscription}
    else
      result ->
        handle_subscription_error_result(
          result,
          "Subscription attempt failed",
          %{plan_id: plan_id}
        )
    end
  end

  def update_subscription(_root, %{subscription_id: subscription_id, plan_id: plan_id}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    user_id = current_user.id

    with {_, %Subscription{user_id: ^user_id} = subscription} <-
           {:subscription?, Subscription.by_id(subscription_id)},
         {_, %Subscription{cancel_at_period_end: false}} <-
           {:not_cancelled?, subscription},
         {_, %Plan{is_deprecated: false} = new_plan} <- {:plan?, Plan.by_id(plan_id)},
         {:ok, subscription} <- Billing.update_subscription(subscription, new_plan) do
      {:ok, subscription}
    else
      result ->
        handle_subscription_error_result(
          result,
          "Upgrade/Downgrade failed",
          %{user_id: user_id, subscription_id: subscription_id, plan_id: plan_id}
        )
    end
  end

  def cancel_subscription(_root, %{subscription_id: subscription_id}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    user_id = current_user.id

    with {_, %Subscription{user_id: ^user_id} = subscription} <-
           {:subscription?, Subscription.by_id(subscription_id)},
         {_, %Subscription{cancel_at_period_end: false}} <-
           {:not_cancelled?, subscription},
         {:ok, cancel_subscription} <-
           Billing.cancel_subscription(subscription) do
      {:ok, cancel_subscription}
    else
      result ->
        handle_subscription_error_result(
          result,
          "Canceling subscription failed",
          %{user_id: user_id, subscription_id: subscription_id}
        )
    end
  end

  def renew_cancelled_subscription(_root, %{subscription_id: subscription_id}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    user_id = current_user.id

    with {_, %Subscription{user_id: ^user_id} = subscription} <-
           {:subscription?, Subscription.by_id(subscription_id)},
         {_, %Subscription{cancel_at_period_end: true}} <- {:cancelled?, subscription},
         {:ok, subscription} <- Billing.renew_cancelled_subscription(subscription) do
      {:ok, subscription}
    else
      result ->
        handle_subscription_error_result(
          result,
          "Renewing subscription failed",
          %{user_id: user_id, subscription_id: subscription_id}
        )
    end
  end

  def payments(_root, _args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    StripeApi.list_payments(current_user)
    |> case do
      {:ok, []} ->
        {:ok, []}

      {:ok, payments} ->
        {:ok, transform_payments(payments)}

      {:error, reason} ->
        log_error("Listing payments failed", reason)
        {:error, Subscription.generic_error_message()}
    end
  end

  def get_coupon(_root, %{coupon: coupon}, _resolution) do
    Sanbase.StripeApi.retrieve_coupon(coupon)
    |> case do
      {:ok,
       %Stripe.Coupon{
         valid: valid,
         id: id,
         name: name,
         percent_off: percent_off,
         amount_off: amount_off
       }} ->
        {:ok,
         %{is_valid: valid, id: id, name: name, percent_off: percent_off, amount_off: amount_off}}

      {:error, %Stripe.Error{message: message} = reason} ->
        log_error("Error checking coupon", reason)
        {:error, message}
    end
  end

  def upcoming_invoice(_root, %{subscription_id: subscription_id}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    current_user_id = current_user.id

    with %Subscription{user_id: ^current_user_id} = subscription <-
           Subscription.by_id(subscription_id),
         true <- subscription.status in [:active, :trialing, :past_due],
         {:ok, %Stripe.Invoice{} = invoice} <- StripeApi.upcoming_invoice(subscription.stripe_id) do
      {:ok,
       %{
         period_start: DateTime.from_unix!(invoice.period_start),
         period_end: DateTime.from_unix!(invoice.period_end),
         amount_due: invoice.total
       }}
    else
      {:error, %Stripe.Error{message: message} = reason} ->
        log_error("Error fetching upcoming invoice", reason)
        {:error, message}

      _ ->
        {:error, "Can't fetch upcoming invoice for the provided subscription"}
    end
  end

  def fetch_default_payment_instrument(_root, _args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    with {:ok, customer} <- StripeApi.fetch_default_card(current_user),
         {:card?, card} when not is_nil(card) <- {:card?, customer.default_source} do
      {:ok,
       %{
         last4: card.last4,
         dynamic_last4: card.dynamic_last4,
         exp_year: card.exp_year,
         exp_month: card.exp_month,
         brand: card.brand,
         funding: card.funding
       }}
    else
      {:card?, nil} ->
        {:error, "Customer has no default payment instrument"}

      {:error, %Stripe.Error{message: message} = reason} ->
        log_error("Error fetching default payment instrument", reason)
        {:error, message}

      _ ->
        {:error, "Can't fetch the default payment instrument"}
    end
  end

  def update_default_payment_instrument(_root, %{card_token: card_token}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    Billing.create_or_update_stripe_customer(current_user, card_token)
    |> case do
      {:ok, _} ->
        {:ok, true}

      {:error, %Stripe.Error{message: message} = reason} ->
        log_error("Update customer card: user=#{inspect(current_user)}", reason)
        {:error, message}

      _ ->
        {:error, "Can't update the default payment instrument"}
    end
  end

  def delete_default_payment_instrument(_root, _args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    case StripeApi.delete_default_card(current_user) do
      :ok ->
        {:ok, true}

      {:error, %Stripe.Error{message: message} = reason} ->
        log_error("Delete customer card: user=#{inspect(current_user)}", reason)
        {:error, message}

      _ ->
        {:error, "Can't delete the default payment instrument"}
    end
  end

  def subscriptions(%User{} = user, _args, _resolution) do
    {:ok, Subscription.user_subscriptions_plus_incomplete(user)}
  end

  def eligible_for_sanbase_trial?(%User{} = user, _args, _resolution) do
    {:ok, Billing.eligible_for_sanbase_trial?(user.id)}
  end

  def san_credit_balance(%User{} = user, _args, _resolution) do
    with {:ok, customer} <- Sanbase.StripeApi.retrieve_customer(user),
         true <- customer.balance < 0 do
      {:ok, -(customer.balance / 100)}
    else
      _ -> {:ok, 0.00}
    end
  end

  def check_annual_discount_eligibility(_root, _args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    {:ok, Subscription.annual_discount_eligibility(current_user.id)}
  end

  # private functions
  defp transform_payments(%Stripe.List{data: payments}) do
    payments
    |> Enum.map(fn
      %Stripe.Charge{
        status: status,
        amount: amount,
        created: created,
        receipt_url: receipt_url,
        description: description
      } ->
        %{
          status: status,
          amount: amount,
          created_at: DateTime.from_unix!(created),
          receipt_url: receipt_url,
          description: description
        }
    end)
  end

  defp handle_subscription_error_result(result, log_message, params) do
    case result do
      {:error, %Stripe.Error{message: message} = reason} ->
        log_error(log_message, reason)
        {:error, message}

      {:error, %Subscription.Error{message: message}} ->
        log_error(log_message, message)
        {:error, message}

      {:plan?, _} ->
        reason = "Cannot find plan with id #{params.plan_id}"
        log_error(log_message, reason)
        {:error, reason}

      {:subscription?, _} ->
        reason =
          "Cannot find subscription with id #{params.subscription_id} for user with id #{params.user_id}. Either this subscription doesn not exist or it does not belong to the user."

        log_error(log_message, reason)
        {:error, reason}

      {:not_cancelled?,
       %Subscription{cancel_at_period_end: true, current_period_end: current_period_end}} ->
        reason =
          "Subscription is scheduled for cancellation at the end of the paid period: #{current_period_end}"

        log_error(log_message, reason)
        {:error, reason}

      {:cancelled?, %Subscription{cancel_at_period_end: false}} ->
        reason = "Subscription is not scheduled for cancellation so it cannot be renewed"

        log_error(log_message, reason)
        {:error, reason}

      {:end_period_reached_error, reason} ->
        log_error(log_message, reason)
        {:error, reason}

      {:error, reason} ->
        log_error(log_message, reason)
        {:error, Subscription.generic_error_message()}
    end
  end

  defp log_error(log_message, reason) do
    Logger.error("#{log_message}. Reason: #{inspect(reason)}")
  end
end
