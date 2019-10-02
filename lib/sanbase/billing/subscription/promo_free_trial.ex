defmodule Sanbase.Billing.Subscription.PromoFreeTrial do
  @moduledoc """
  Free trial subscription to all products for devcon participants.
  """
  require Logger

  import Ecto.Query

  alias Sanbase.StripeApi
  alias Sanbase.Auth.User
  alias Sanbase.Billing.{Subscription, Plan}
  alias Sanbase.Repo

  @promo_code_stats %{
    "devcon2019" => %{
      # API Pro, Sanbase Pro and Grafana Pro
      # Fixme add grafana plan here
      promo_plans: [3, 13],
      cancel_after_days: 14,
      coupon_args: %{
        name: "Devcon 2019 santiment free trial",
        percent_off: 100,
        duration: "once",
        max_redemptions: 3,
        redeem_by: Sanbase.DateTimeUtils.from_iso8601_to_unix!("2019-11-01T00:00:00Z"),
        metadata: %{"current_promotion" => "devcon2019"}
      }
    }
  }

  @current_promotions ["devcon2019"]
  @generic_error_message "Error creating promotional subscription."

  def generic_error_message(), do: @generic_error_message

  def promo_code_stats, do: @promo_code_stats

  def create_promo_subscription(%User{stripe_customer_id: stripe_customer_id} = user, coupon)
      when is_binary(stripe_customer_id) do
    with {:ok, coupon} <- check_coupon(coupon),
         {:ok, subscriptions} <- promo_subscribe(user, coupon) do
      {:ok, subscriptions}
    else
      {:error, error} ->
        handle_error(user, error)
    end
  end

  def create_promo_subscription(%User{} = user, coupon) do
    with {:ok, coupon} <- check_coupon(coupon),
         {:ok, user} <- Subscription.create_or_update_stripe_customer(user),
         {:ok, subscriptions} <- promo_subscribe(user, coupon) do
      {:ok, subscriptions}
    else
      {:error, error} ->
        handle_error(user, error)
    end
  end

  defp promo_subscribe(user, coupon) do
    promo_plans = get_in(@promo_code_stats, [coupon.metadata["current_promotion"], :promo_plans])

    from(p in Plan, where: p.id in ^promo_plans)
    |> Repo.all()
    |> Enum.map(&promo_subscribe(user, &1, coupon))
    |> Enum.filter(&match?({:error, _}, &1))
    |> case do
      [] ->
        {:ok, Subscription.user_subscriptions(user)}

      # we are subscribing to multiple plans so any of them can fail
      [error | _] ->
        error
    end
  end

  defp promo_subscribe(user, plan, coupon) do
    with {:ok, stripe_subscription} <-
           promotional_subsciption_data(user, plan, coupon) |> StripeApi.create_subscription(),
         {:ok, subscription} <-
           Subscription.create_subscription_db(stripe_subscription, user, plan) do
      {:ok, subscription}
    end
  end

  defp promotional_subsciption_data(user, plan, coupon) do
    cancel_after_days =
      get_in(@promo_code_stats, [coupon.metadata["current_promotion"], :cancel_after_days])

    %{
      customer: user.stripe_customer_id,
      items: [%{plan: plan.stripe_id}],
      cancel_at: Timex.shift(Timex.now(), days: cancel_after_days) |> DateTime.to_unix(),
      coupon: coupon.id
    }
  end

  defp check_coupon(coupon_id) do
    with {:ok, coupon} <- StripeApi.retrieve_coupon(coupon_id),
         true <- coupon.valid and coupon.metadata["current_promotion"] in @current_promotions do
      {:ok, coupon}
    else
      {:error, %Stripe.Error{} = error} ->
        {:error, error}

      _ ->
        {:error, "The coupon code is not valid or the promotion is outdated."}
    end
  end

  defp handle_error(user, error) do
    case error do
      %Stripe.Error{message: message} = error ->
        log(user, error)
        {:error, message}

      error_msg when is_binary(error_msg) ->
        log(user, error)
        {:error, error_msg}

      error ->
        log(user, error)
        {:error, @generic_error_message}
    end
  end

  defp log(user, error) do
    Logger.error(
      "Error creating promotional subscription for user: #{inspect(user)}, reason: #{
        inspect(error)
      }"
    )
  end
end
