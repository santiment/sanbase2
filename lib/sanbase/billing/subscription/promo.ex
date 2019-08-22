defmodule Sanbase.Billing.Subscription.Promo do
  @public_promo_code_stats %{
    "DEVCON" => %{
      # Highest plans from API, Sanbase and Sheets
      plans: [5, 14, 24],
      cancel_after_days: 14
    }
  }

  @public_promo_codes Map.keys(@public_promo_code_stats)

  @moduledoc """
  Implements a way to create promotional subscriptions.
  These are subscriptions with specific discount code that give access to some predefined plans
  for a limited amount of time at a discount price (mostly free).

  The multi use promo subscription is modelled by #{inspect(@public_promo_code_stats)} map.
  The keys contain the public discount id previously created in Stripe. It can contain information
  about the `percent_off`, the date by which the code should be redeemed.
  The values contain info about:
    * for which plans the customer should be subscribed
    * for how much time the customer should be subscribed
  """
  require Logger

  import Ecto.Query

  alias Sanbase.StripeApi
  alias Sanbase.Auth.User
  alias Sanbase.Billing.{Subscription, Plan}
  alias Sanbase.Repo

  def create_promo_subscription(%User{stripe_customer_id: stripe_customer_id} = user, coupon)
      when is_binary(stripe_customer_id) and coupon in @public_promo_codes do
    promo_subscribe(user, coupon)
  end

  def create_promo_subscription(%User{} = user, coupon) when coupon in @public_promo_codes do
    Subscription.create_or_update_stripe_customer(user)
    |> case do
      {:ok, user} ->
        promo_subscribe(user, coupon)

      {:error, error} ->
        Logger.error(
          "Error creating promotional subscription for user: #{inspect(user)}, reason: #{
            inspect(error)
          }"
        )

        {:error, Subscription.generic_error_message()}
    end
  end

  def create_promo_subscription(_, _), do: {:error, "Unsupported promotional code"}

  defp promo_subscribe(user, coupon) do
    promo_plans = get_in(@public_promo_code_stats, [coupon, :plans])

    from(p in Plan, where: p.id in ^promo_plans)
    |> Repo.all()
    |> Enum.map(&promo_subscribe(user, &1, coupon))
    |> Enum.filter(&match?({:error, _}, &1))
    |> case do
      [] ->
        {:ok, Subscription.user_subscriptions(user)}

      errors ->
        Logger.error(
          "Error creating promotional subscription for user: #{inspect(user)}, reason: #{
            inspect(errors)
          }"
        )

        {:error, Subscription.generic_error_message()}
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
    cancel_after_days = get_in(@public_promo_code_stats, [coupon, :cancel_after_days])

    %{
      customer: user.stripe_customer_id,
      items: [%{plan: plan.stripe_id}],
      cancel_at: Timex.shift(Timex.now(), days: cancel_after_days) |> DateTime.to_unix(),
      coupon: coupon
    }
  end
end
