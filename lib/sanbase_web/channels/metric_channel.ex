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
        socket = initiate_socket(socket, params)

        {:ok, socket}

      false ->
        {:error, "The channel subtopic must be the authenticated user id"}
    end
  end

  def handle_in("subscribe_slugs", %{"slugs" => slugs}, socket) do
    socket = subscribe_items(socket, :slugs, :unsubscribed_slugs, slugs)
    {:noreply, socket}
  end

  def handle_in("unsubscribe_slugs", %{"slugs" => slugs}, socket) do
    socket = unsubscribe_items(socket, :slugs, :unsubscribed_slugs, slugs)
    {:noreply, socket}
  end

  def handle_in("subscribe_metrics", %{"metrics" => metrics}, socket) do
    socket = subscribe_items(socket, :metrics, :unsubscribed_metrics, metrics)
    {:noreply, socket}
  end

  def handle_in("unsubscribe_metrics", %{"metrics" => metrics}, socket) do
    socket = unsubscribe_items(socket, :metrics, :unsubscribed_metrics, metrics)
    {:noreply, socket}
  end

  def handle_out("metric_data", data, socket) do
    %{
      slugs: slugs,
      unsubscribed_slugs: uslugs,
      metrics: metrics,
      unsubscribed_metrics: umetrics
    } = socket.assigns

    %{"slug" => slug, "metric" => metric} = data

    with true <- (slugs != :all and slug in slugs) or (slugs == :all and slug not in uslugs),
         true <-
           (metrics != :all and metric in metrics) or (metrics == :all and metric not in umetrics) do
      push(socket, "metric_data", data)
    end

    {:noreply, socket}
  end

  # Private functions

  defp initiate_socket(socket, params) do
    slugs = if slugs = params["slugs"], do: MapSet.new(slugs), else: :all
    metrics = if metrics = params["metrics"], do: MapSet.new(metrics), else: :all

    socket
    |> assign(:slugs, slugs)
    |> assign(:unsubscribed_slugs, MapSet.new([]))
    |> assign(:metrics, metrics)
    |> assign(:unsubscribed_metrics, MapSet.new([]))
  end

  # ukey = unsubscribed_key
  defp subscribe_items(socket, key, ukey, items) do
    items = MapSet.new(items)

    case {socket.assigns[key], socket.assigns[ukey]} do
      {:all, umapset} ->
        socket
        |> assign(ukey, MapSet.difference(umapset, items))

      {mapset, umapset} ->
        socket
        |> assign(key, MapSet.union(mapset, items))
        |> assign(ukey, MapSet.difference(umapset, items))
    end
  end

  defp unsubscribe_items(socket, key, ukey, items) do
    items = MapSet.new(items)

    case {socket.assigns[key], socket.assigns[ukey]} do
      {:all, umapset} ->
        socket
        |> assign(ukey, MapSet.union(umapset, items))

      {mapset, umapset} ->
        socket
        |> assign(key, MapSet.difference(mapset, items))
        |> assign(ukey, MapSet.union(umapset, items))
    end
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
