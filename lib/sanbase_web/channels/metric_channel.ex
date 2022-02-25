defmodule SanbaseWeb.MetricChannel do
  use SanbaseWeb, :channel

  intercept(["metric_data"])

  # metrics group is a string identifying metrics:
  # "all" - all metrics. Available in PRO+ and SanAPI PRO.
  #         3 connections per user are allowed
  # "price" - price metrics.
  # "onchain"
  # "social"
  def join("metrics:" <> metrics_group, params, socket) do
    case user_has_access?(socket.assigns.user, metrics_group) do
      true ->
        slugs =
          case Map.get(params, "slugs", :all) do
            :all -> :all
            [_ | _] = slugs -> MapSet.new(slugs)
          end

        {:ok, assign(socket, :slugs, slugs)}

      false ->
        {:error, "The channel subtopic must be the authenticated user id"}
    end
  end

  def handle_in("subscribe_slugs", %{"slugs" => slugs}, socket) do
    new_slugs = MapSet.union(socket.assigns.slugs, MapSet.new(slugs))
    {:noreply, assign(socket, :slugs, new_slugs)}
  end

  def handle_in("unsubscribe_slugs", %{"slugs" => slugs}, socket) do
    new_slugs = MapSet.difference(socket.assigns.slugs, MapSet.new(slugs))
    {:noreply, assign(socket, :slugs, new_slugs)}
  end

  def handle_out("metric_data", data, socket) do
    if socket.assigns.slugs == :all or data["slug"] in socket.assigns.slugs do
      push(socket, "metric_data", data)
    end

    {:noreply, socket}
  end

  defp user_has_access?(user, metrics_group) do
    user_subscriptions = Sanbase.Billing.Subscription.user_subscription_names(user)

    cond do
      metrics_group == "price" ->
        true

      metrics_group == "onchain" and
          not subscriptions_include_pro?(user_subscriptions) ->
        false

      true ->
        true
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
