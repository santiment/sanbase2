defmodule Sanbase.Billing.Subscription.PromoTrial do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  require Logger

  alias Sanbase.Billing
  alias Sanbase.StripeApi
  alias Sanbase.Accounts.User
  alias Sanbase.Billing.{Subscription, Plan}
  alias Sanbase.Repo

  @plan_id_name_map %{
    "3" => "SanAPI by Santiment / PRO",
    "5" => "SanAPI by Santiment / PRO",
    "201" => "Sanbase by Santiment / PRO",
    "43" => "Sandata by Santiment / PREMIUM"
  }

  # API Pro, API custom, Sanbase Pro and Grafana Premium
  @promo_trial_plans [3, 5, 201, 43]

  schema "promo_trials" do
    field(:trial_days, :integer)
    field(:plans, {:array, :string})
    belongs_to(:user, User)

    timestamps()
  end

  def changeset(%__MODULE__{} = promo_trial, attrs \\ %{}) do
    promo_trial
    |> cast(attrs, [
      :user_id,
      :trial_days,
      :plans
    ])
    |> stringify_plans(attrs)
  end

  def promo_trial_plans, do: @promo_trial_plans

  def create_promo_trial(%{plans: plans, trial_days: trial_days, user_id: user_id}) do
    {:ok, user} = User.by_id(user_id)

    plans =
      plans
      |> Enum.map(&maybe_convert_to_integer?/1)

    trial_days = maybe_convert_to_integer?(trial_days)

    create_promo_subscription(user, plans, trial_days)
  end

  defp create_promo_subscription(
         %User{stripe_customer_id: stripe_customer_id} = user,
         plans,
         trial_days
       )
       when is_binary(stripe_customer_id) do
    case promo_subscribe(user, plans, trial_days) do
      {:ok, subscriptions} ->
        {:ok, subscriptions}

      {:error, error} ->
        handle_error(user, error)
    end
  end

  defp create_promo_subscription(%User{} = user, plans, trial_days) do
    with {:ok, user} <- Billing.create_or_update_stripe_customer(user),
         {:ok, subscriptions} <- promo_subscribe(user, plans, trial_days) do
      {:ok, subscriptions}
    else
      {:error, error} ->
        handle_error(user, error)
    end
  end

  defp promo_subscribe(user, plans, trial_days) do
    from(p in Plan, where: p.id in ^plans)
    |> Repo.all()
    |> Enum.map(&subscribe_to_plan(user, &1, trial_days))
    |> Enum.filter(&match?({:error, _}, &1))
    |> case do
      [] ->
        {:ok, Subscription.user_subscriptions(user)}

      # we are subscribing to multiple plans so any of them can fail
      [error | _] ->
        error
    end
  end

  defp subscribe_to_plan(user, plan, trial_days) do
    with {:ok, stripe_subscription} <-
           promotional_subsciption_data(user, plan, trial_days) |> StripeApi.create_subscription(),
         {:ok, subscription} <-
           Subscription.create_subscription_db(stripe_subscription, user, plan),
         {:ok, _} <- Sanbase.ApiCallLimit.update_user_plan(user) do
      {:ok, subscription}
    end
  end

  defp promotional_subsciption_data(user, plan, trial_days) do
    %{
      customer: user.stripe_customer_id,
      items: [%{plan: plan.stripe_id}],
      trial_end: Timex.shift(Timex.now(), days: trial_days) |> DateTime.to_unix()
    }
  end

  defp handle_error(user, error) do
    case error do
      %Stripe.Error{message: message} = error ->
        log_error(user, error)
        {:error, message}

      error_msg when is_binary(error_msg) ->
        log_error(user, error)
        {:error, error_msg}

      error ->
        log_error(user, error)
        {:error, error}
    end
  end

  defp log_error(user, error) do
    Logger.error(
      "Error creating promotional subscription for user: #{inspect(user)}, reason: #{
        inspect(error)
      }"
    )
  end

  defp stringify_plans(changeset, %{plans: plans}) do
    put_change(changeset, :plans, Enum.map(plans, &@plan_id_name_map[&1]))
  end

  defp stringify_plans(changeset, _), do: changeset

  defp maybe_convert_to_integer?(value) when is_integer(value) do
    value
  end

  defp maybe_convert_to_integer?(value) when is_binary(value) do
    String.to_integer(value)
  end
end
