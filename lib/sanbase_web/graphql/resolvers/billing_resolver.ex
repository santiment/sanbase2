defmodule SanbaseWeb.Graphql.Resolvers.BillingResolver do
  alias Sanbase.Billing.{Subscription, Plan}
  alias Sanbase.Auth.User

  alias Sanbase.StripeApi

  require Logger

  def products_with_plans(_root, _args, _resolution) do
    Plan.product_with_plans()
  end

  def update_customer_card(_root, %{card_token: card_token}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    Subscription.create_or_update_stripe_customer(current_user, card_token)
    |> case do
      {:ok, _} ->
        {:ok, %{success: true}}

      {:error, %Stripe.Error{message: message} = reason} ->
        Logger.error(
          "Update customer card: user=#{inspect(current_user)} reason=#{inspect(reason)}"
        )

        {:error, message}
    end
  end

  def subscribe(_root, %{plan_id: plan_id} = args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    card_token = Map.get(args, :card_token)
    coupon = Map.get(args, :coupon)

    with {:plan?, %Plan{is_deprecated: false} = plan} <- {:plan?, Plan.by_id(plan_id)},
         {:ok, subscription} <-
           Subscription.subscribe(current_user, plan, card_token, coupon) do
      {:ok, subscription}
    else
      result ->
        handle_subscription_error_result(result, "Subscription attempt failed", %{
          plan_id: plan_id
        })
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
         {:ok, subscription} <- Subscription.update_subscription(subscription, new_plan) do
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
           Subscription.cancel_subscription(subscription) do
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
         {_, %Subscription{cancel_at_period_end: true}} <-
           {:cancelled?, subscription},
         {:ok, subscription} <- Subscription.renew_cancelled_subscription(subscription) do
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
        Logger.error("Listing payments failed: reason: #{inspect(reason)}")
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
        Logger.error("Error checking coupon: #{inspect(reason)}")
        {:error, message}
    end
  end

  def subscriptions(%User{} = user, _args, _resolution) do
    {:ok, Subscription.user_subscriptions(user)}
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
      {:plan?, _} ->
        reason = "Cannot find plan with id #{params.plan_id}"
        Logger.error("#{log_message} - reason: #{reason}")
        {:error, reason}

      {:subscription?, _} ->
        reason =
          "Cannot find subscription with id #{params.subscription_id} for user with id #{params.user_id}. Either this subscription doesn not exist or it does not belong to the user."

        Logger.error("#{log_message} - reason: #{reason}")
        {:error, reason}

      {:not_cancelled?,
       %Subscription{cancel_at_period_end: true, current_period_end: current_period_end}} ->
        reason =
          "Subscription is scheduled for cancellation at the end of the paid period: #{current_period_end}"

        Logger.error("#{log_message} - reason: #{reason}")
        {:error, reason}

      {:cancelled?, %Subscription{cancel_at_period_end: false}} ->
        reason = "Subscription is not scheduled for cancellation so it cannot be renewed"

        Logger.error("#{log_message} - reason: #{reason}")
        {:error, reason}

      {:end_period_reached_error, reason} ->
        Logger.error("#{log_message} - reason: #{inspect(reason)}")
        {:error, reason}

      {:error, reason} ->
        Logger.error("#{log_message} - reason: #{inspect(reason)}")
        {:error, Subscription.generic_error_message()}
    end
  end
end
