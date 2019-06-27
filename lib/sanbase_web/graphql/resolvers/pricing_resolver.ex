defmodule SanbaseWeb.Graphql.Resolvers.PricingResolver do
  alias Sanbase.Pricing.{Subscription, Plan}
  alias Sanbase.Auth.User
  alias Sanbase.Repo

  require Logger

  def products_with_plans(_root, _args, _resolution) do
    Plan.product_with_plans()
  end

  def subscribe(_root, %{card_token: card_token, plan_id: plan_id}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    with {:plan?, %Plan{} = plan} <- {:plan?, Repo.get(Plan, plan_id)},
         {:ok, subscription} <- Subscription.subscribe(current_user, card_token, plan) do
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

    with {:subscription?, %Subscription{user_id: ^user_id} = subscription} <-
           {:subscription?, Repo.get(Subscription, subscription_id) |> Repo.preload(:plan)},
         {:plan?, %Plan{} = new_plan} <- {:plan?, Repo.get(Plan, plan_id)},
         {:ok, subscription} <- Subscription.update_subscription(subscription, new_plan) do
      {:ok, subscription}
    else
      result ->
        handle_subscription_error_result(
          result,
          "Upgrade/Downgrade failed",
          %{user_id: current_user.id, subscription_id: subscription_id, plan_id: plan_id}
        )
    end
  end

  def cancel_subscription(_root, %{subscription_id: subscription_id}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    user_id = current_user.id

    with {:subscription?, %Subscription{user_id: ^user_id} = subscription} <-
           {:subscription?, Repo.get(Subscription, subscription_id)},
         {:ok, cancel_subscription} <- Subscription.cancel_subscription(subscription) do
      {:ok, cancel_subscription}
    else
      result ->
        handle_subscription_error_result(
          result,
          "Canceling subscription failed",
          %{user_id: current_user.id, subscription_id: subscription_id}
        )
    end
  end

  def subscriptions(%User{} = user, _args, _resolution) do
    {:ok, Subscription.user_subscriptions(user)}
  end

  # private functions
  defp handle_subscription_error_result(result, log_message, params) do
    case result do
      {:plan?, _} ->
        reason = "Cannot find plan with id #{params.plan_id}"
        Logger.error("#{log_message} - reason: #{reason}")
        {:error, reason}

      {:subscription?, _} ->
        reason =
          "Cannot find subscription with id #{params.subscription_id} for user with id #{
            params.user_id
          }. Either this subscription doesn not exist or it does not belong to the user."

        Logger.error("#{log_message} - reason: #{reason}")
        {:error, reason}

      {:error, reason} ->
        Logger.error("#{log_message} - reason: #{inspect(reason)}")
        {:error, Subscription.generic_error_message()}
    end
  end
end
