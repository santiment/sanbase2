defmodule Sanbase.Billing.Subscription.Promo do
  require Logger

  import Ecto.Query

  alias Sanbase.StripeApi
  alias Sanbase.Auth.User
  alias Sanbase.Billing.{Subscription, Plan}
  alias Sanbase.Repo

  @promo_trial_period_days 14
  @doc """
  Enterprise plans from API, Sanbase and Sheets products are used for #{@promo_trial_period_days} days
  promotional free trial of our services.
  """
  @promo_plans [5, 14, 24]
  @promo_metadata %{"promo_event" => "devcon2019"}

  @doc """
  Attach a subscription with a free trial of #{@promo_trial_period_days} days for all highest priced plans for all
  products to the user. It doesn't require a credit card.
  """
  def promo_subscription(%User{stripe_customer_id: stripe_customer_id} = user)
      when is_binary(stripe_customer_id) do
    promo_subscribe(user)
  end

  def promo_subscription(%User{} = user) do
    Subscription.create_or_update_stripe_customer(user)
    |> case do
      {:ok, user} ->
        promo_subscribe(user)

      {:error, error} ->
        Logger.error(
          "Error creating promotional subscription for user: #{inspect(user)}, reason: #{
            inspect(error)
          }"
        )

        {:error, Subscription.generic_error_message()}
    end
  end

  defp promo_subscribe(user) do
    from(p in Plan, where: p.id in ^@promo_plans)
    |> Repo.all()
    |> Enum.map(&promo_subscribe(user, &1))
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

  defp promo_subscribe(user, plan) do
    with {:ok, stripe_subscription} <-
           promotional_subsciption_data(user, plan) |> StripeApi.create_subscription(),
         {:ok, subscription} <-
           Subscription.create_subscription_db(stripe_subscription, user, plan) do
      {:ok, subscription}
    end
  end

  defp promotional_subsciption_data(user, plan) do
    %{
      customer: user.stripe_customer_id,
      items: [%{plan: plan.stripe_id}],
      trial_period_days: @promo_trial_period_days,
      metadata: @promo_metadata,
      cancel_at: Timex.shift(Timex.now(), days: @promo_trial_period_days) |> DateTime.to_unix()
    }
  end
end
