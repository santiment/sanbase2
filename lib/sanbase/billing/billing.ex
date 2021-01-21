defmodule Sanbase.Billing do
  @moduledoc ~s"""
  Context module for all billing functionality
  """

  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Billing.{Product, Plan, Subscription}
  alias Sanbase.Billing.Subscription.{FreeSubscription, SignUpTrial}

  defdelegate create_trial_subscription(user_id), to: SignUpTrial
  # FreeSubscription
  defdelegate create_free_subscription(user_id), to: FreeSubscription
  defdelegate remove_free_subscription(free_subscription), to: FreeSubscription
  defdelegate list_free_subscriptions(), to: FreeSubscription
  defdelegate eligible_for_free_subscription?(user_id), to: FreeSubscription
  defdelegate user_has_active_sanbase_subscriptions?(user_id), to: FreeSubscription
  defdelegate sync_free_subscriptions_staked_users(), to: FreeSubscription
  defdelegate maybe_create_free_subscriptions_staked_users(), to: FreeSubscription
  defdelegate maybe_remove_free_subscriptions_staked_users(), to: FreeSubscription

  def list_products(), do: Repo.all(Product)

  def list_plans() do
    from(p in Plan, preload: [:product])
    |> Repo.all()
  end

  @doc ~s"""
  Sync the locally defined Products and Plans with stripe.

  This acction assings a `stripe_id` to every product and plan without which
  no subscription can succeed.

  In order to create the Products and Plans locally, the seed
  `priv/repo/seed_plans_and_products.exs` must be executed.
  """
  @spec sync_with_stripe() :: :ok | {:error, %Stripe.Error{}}
  def sync_with_stripe() do
    with :ok <- run_sync(list_products(), &Product.maybe_create_product_in_stripe/1),
         :ok <- run_sync(list_plans(), &Plan.maybe_create_plan_in_stripe/1) do
      :ok
    else
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  If user has enough SAN staked and has no active Sanbase subscription - create one
  Or if user is not yet registered - create a 14 day trial
  """
  @spec maybe_create_free_or_trial_subscription(non_neg_integer()) ::
          {:ok, %Subscription{}} | {:ok, %SignUpTrial{}} | {:error, any()}
  def maybe_create_free_or_trial_subscription(user_id) do
    case eligible_for_free_subscription?(user_id) do
      true -> create_free_subscription(user_id)
      false -> create_trial_subscription(user_id)
    end
  end

  # Private functions

  # Return :ok if all function calls over the list return {:ok, _}
  # Return the error otherwise
  defp run_sync(list, function) when is_function(function, 1) do
    Enum.map(list, function)
    |> Enum.find(:ok, fn
      {:ok, _} -> false
      {:error, _} -> true
    end)
  end
end
