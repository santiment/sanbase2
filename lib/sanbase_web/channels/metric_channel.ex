defmodule SanbaseWeb.MetricChannel do
  use SanbaseWeb, :channel

  # metrics group is a string identifying metrics:
  # "all" - all metrics. Available in PRO+ and SanAPI PRO.
  #         3 connections per user are allowed
  # "price" - price metrics.
  # "onchain"
  # "social"
  def join("metrics:" <> metrics_group, _params, socket) do
    case user_has_access?(socket.assigns.user, metrics_group) do
      true ->
        {:ok, socket}

      false ->
        {:error, "The channel subtopic must be the authenticated user id"}
    end
  end

  def handle_in("is_username_valid", %{"username" => username}, socket) do
    case Sanbase.Accounts.User.Name.valid_username?(username) do
      true ->
        {:reply, {:ok, %{"is_username_valid" => true}}, socket}

      {:error, reason} ->
        {:reply, {:ok, %{"is_username_valid" => false, "reason" => reason}}, socket}
    end
  end

  defp user_has_access?(user, metrics_group) do
    user_subscriptions = Sanbase.Billing.Subscription.user_subscription_names(user)

    cond do
      metrics_group == "price" -> true
      metrics_group == "onchain" and not subscriptions_include_pro?(user_subscriptions) -> false
      true -> true
    end
  end

  defp subscriptions_include_pro?(subscriptions) do
    Enum.any?(subscriptions, fn sub ->
      sub in [
        "Sanbase by Santiment / PRO_PLUS",
        "Sanbase by Santiment / PRO",
        "SanAPI by Santiment / PRO"
      ]
    end)
  end
end
