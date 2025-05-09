defmodule SanbaseWeb.Graphql.Resolvers.BillingResolver do
  alias Sanbase.Billing
  alias Sanbase.Billing.Subscription
  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.UserPromoCode
  alias Sanbase.Billing.Plan.PurchasingPowerParity

  alias Sanbase.Accounts.User

  alias Sanbase.StripeApi

  require Logger

  def products_with_plans(_root, _args, %{context: %{remote_ip: remote_ip}}) do
    remote_ip = Sanbase.Utils.IP.ip_tuple_to_string(remote_ip)
    Sanbase.Geoip.Data.find_or_insert(remote_ip)

    Plan.product_with_plans()
  end

  def ppp_settings(_root, _args, %{context: %{remote_ip: remote_ip}}) do
    remote_ip = Sanbase.Utils.IP.ip_tuple_to_string(remote_ip)

    with {:ok, geoip_data} <- Sanbase.Geoip.Data.find_or_insert(remote_ip),
         true <- PurchasingPowerParity.ip_eligible_for_ppp?(geoip_data.ip_address) do
      {:ok, PurchasingPowerParity.ppp_settings(geoip_data)}
    else
      _ -> {:ok, %{is_eligible_for_ppp: false}}
    end
  end

  def subscribe(_root, %{plan_id: plan_id} = args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    payment_instrument = Map.take(args, [:card_token, :payment_method_id])
    coupon = Map.get(args, :coupon)

    with {_, %Plan{is_deprecated: false} = plan} <- {:plan?, Plan.by_id(plan_id)},
         true <- UserPromoCode.is_coupon_usable(coupon, plan),
         {:ok, subscription} <- route_subscription(current_user, plan, payment_instrument, coupon) do
      # If the coupon exists in the user_promo_codes table, times_redeemed
      # will be bumped by one. We don't check beforehand if the coupon exists and if it's valid,
      # as the Stripe API will take care of this.
      if coupon, do: UserPromoCode.use_coupon(coupon)

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

  def pay_now(_root, %{subscription_id: subscription_id}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    Subscription.pay_now(current_user, subscription_id)
  end

  def route_subscription(current_user, plan, payment_instrument, coupon) do
    case payment_instrument do
      %{payment_method_id: payment_method_id} when is_binary(payment_method_id) ->
        Subscription.subscribe2(current_user, plan, payment_method_id, coupon)

      %{card_token: card_token} when is_binary(card_token) ->
        Billing.subscribe(current_user, plan, card_token, coupon)

      _ ->
        Billing.subscribe(current_user, plan, nil, coupon)
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

  def get_subscription_with_payment_intent(_root, %{subscription_id: subscription_id}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    user_id = current_user.id

    with {_, %Subscription{user_id: ^user_id} = subscription} <-
           {:subscription?, Subscription.by_id(subscription_id)},
         {:ok, stripe_subscription} <- StripeApi.retrieve_subscription(subscription.stripe_id) do
      Subscription.sync_subscription_with_stripe(stripe_subscription, subscription)
    else
      result ->
        handle_subscription_error_result(
          result,
          "Fetching latest payment intent failed",
          %{user_id: user_id, subscription_id: subscription_id}
        )
    end
  end

  def cancel_subscription_at_period_end(_root, %{subscription_id: subscription_id}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    user_id = current_user.id

    with {_, %Subscription{user_id: ^user_id} = subscription} <-
           {:subscription?, Subscription.by_id(subscription_id)},
         {_, %Subscription{cancel_at_period_end: false}} <-
           {:not_cancelled?, subscription},
         {:ok, cancel_subscription_at_period_end} <-
           Billing.cancel_subscription_at_period_end(subscription) do
      {:ok, cancel_subscription_at_period_end}
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

  def get_coupon(_root, %{coupon: coupon}, %{
        context: %{remote_ip: remote_ip, auth: %{current_user: current_user}}
      }) do
    remote_ip = Sanbase.Utils.IP.ip_tuple_to_string(remote_ip)

    with :ok <- Sanbase.Accounts.CouponAttempt.check_attempt_limit(current_user, remote_ip),
         {:ok, _} <- Sanbase.Accounts.CouponAttempt.create(current_user, remote_ip),
         {:ok,
          %Stripe.Coupon{
            valid: valid,
            id: id,
            name: name,
            percent_off: percent_off,
            amount_off: amount_off
          }} <- Sanbase.StripeApi.retrieve_coupon(coupon) do
      {:ok,
       %{
         is_valid: valid,
         id: id,
         name: name,
         percent_off: percent_off,
         amount_off: amount_off
       }}
    else
      {:error, :too_many_attempts} ->
        {:error, "Too many coupon attempts. Please try again later."}

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
    with {:ok, customer} <- StripeApi.fetch_stripe_customer(current_user),
         {:card?, card} when not is_nil(card) <- {:card?, choose_default_card(customer)} do
      {:ok,
       %{
         last4: card.last4,
         # dynamic_last4 might not be present
         dynamic_last4: card[:dynamic_last4],
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

  def obtain_sanr_nft_subscription(_root, _args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    has_active_subscription? =
      if Subscription.user_has_active_sanbase_subscriptions?(current_user.id) do
        {:error, "The user already has an active Sanbase subscription"}
      else
        false
      end

    addresses = Sanbase.Accounts.EthAccount.all_by_user(current_user.id) |> Enum.map(& &1.address)

    has_accounts_linked? =
      if [] == addresses do
        {:error, "The user does not have any blockchain addresses connected"}
      else
        true
      end

    token_data = Sanbase.SmartContracts.SanrNFT.get_latest_valid_nft_token(addresses)

    has_sanr_nft_token? =
      case token_data do
        {:ok, _} ->
          true

        {:error, _} ->
          {:error,
           "The user is not eligible for the SanR NFT subscription. None of user addresses has a valid SanR NFT token."}
      end

    with false <- has_active_subscription?,
         true <- has_accounts_linked?,
         true <- has_sanr_nft_token? do
      {:ok, %{end_date: end_date}} = token_data

      Subscription.NFTSubscription.create_nft_subscription(
        current_user.id,
        :sanr_points_nft,
        end_date
      )
    end
  end

  def check_sanr_nft_subscription_eligibility(_root, _args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    addresses = Sanbase.Accounts.EthAccount.all_by_user(current_user.id) |> Enum.map(& &1.address)

    case Sanbase.SmartContracts.SanrNFT.get_latest_valid_nft_token(addresses) do
      {:ok, _} -> {:ok, true}
      {:error, _} -> {:ok, false}
    end
  end

  # Private functions

  # default card can be either a card token or a payment method
  # they are stored in different places in the customer object
  defp choose_default_card(customer) do
    cond do
      # Check for default payment method first
      is_map(customer.invoice_settings) and customer.invoice_settings.default_payment_method ->
        pm_id = customer.invoice_settings.default_payment_method
        {:ok, pm} = StripeApi.retrieve_payment_method(pm_id)
        pm.card

      # Fall back to default source if it exists and is a card
      customer.default_source && is_struct(customer.default_source, Stripe.Card) ->
        Map.from_struct(customer.default_source)

      # Handle card source type
      customer.default_source && is_map(customer.default_source) &&
          Map.get(customer.default_source, :type) == "card" ->
        get_in(customer.default_source, [:card]) || customer.default_source

      true ->
        nil
    end
  end

  def update_default_payment_instrument(_root, %{card_token: card_token}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    if current_user.stripe_customer_id do
      StripeApi.maybe_detach_payment_method(current_user.stripe_customer_id)
    end

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

  def create_stripe_setup_intent(_root, _args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    case StripeApi.create_setup_intent(current_user) do
      {:ok, setup_intent} ->
        {:ok, %{client_secret: setup_intent.client_secret}}

      {:error, %Stripe.Error{message: message} = reason} ->
        log_error("Create setup intent: user=#{inspect(current_user)}", reason)
        {:error, message}

      _ ->
        {:error, "Can't create setup intent"}
    end
  end

  def subscriptions(%User{} = user, _args, _resolution) do
    {:ok, Subscription.user_subscriptions_plus_incomplete(user)}
  end

  def public_user_subscriptions(%User{} = user, _args, _resolution) do
    subscriptions = Subscription.user_subscriptions_plus_incomplete(user)

    public_subscriptions =
      Enum.map(subscriptions, fn sub ->
        %{
          plan_name: Plan.plan_name(sub.plan),
          product_name: sub.plan.product.code
        }
      end)

    {:ok, public_subscriptions}
  end

  def eligible_for_sanbase_trial?(%User{} = user, _args, _resolution) do
    {:ok, Billing.eligible_for_sanbase_trial?(user.id)}
  end

  def eligible_for_api_trial?(%User{} = user, _args, _resolution) do
    {:ok, Billing.eligible_for_api_trial?(user.id)}
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
