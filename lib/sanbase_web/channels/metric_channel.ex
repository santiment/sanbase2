defmodule SanbaseWeb.MetricChannel do
  use SanbaseWeb, :channel

  @compile {:inline, is_subscribed?: 3}
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
      unsubscribed_metrics: umetrics,
      sources: sources,
      unsubscribed_sources: usources
    } = socket.assigns

    %{"slug" => slug, "metric" => metric, "metadata" => metadata} = data

    # The `metric_data` messages are intercepted in order to check if the
    # channel should receive them. The channel can be subscribed not to the
    # whole topic but only to some of the slugs/metrics/sources/etc. Only if
    # all checks are passed, the message is sent to the channel.
    with true <- is_subscribed?(slug, slugs, uslugs),
         true <- is_subscribed?(metric, metrics, umetrics),
         true <- is_subscribed?(metadata["source"] || :do_not_check, sources, usources) do
      push(socket, "metric_data", data)
    end

    {:noreply, socket}
  end

  defp is_subscribed?(:do_not_check, _, _), do: true

  # The check if a `metric_data` should be sent is done based on multiple criteria.
  # These include checking if the slug/metric/source/etc. are in the lists of
  # subscribed or unsubscribed entities.
  # The check is split into two main checks based on whether the channel was
  # created with no restrictions or some restrictions.
  defp is_subscribed?(item, subscribed_items, unsubscribed_items) do
    (subscribed_items != :all and item in subscribed_items) or
      (subscribed_items == :all and item not in unsubscribed_items)
  end

  # Private functions

  defp initiate_socket(socket, params) do
    slugs = if slugs = params["slugs"], do: MapSet.new(slugs), else: :all
    metrics = if metrics = params["metrics"], do: MapSet.new(metrics), else: :all
    sources = if sources = params["sources"], do: MapSet.new(sources), else: :all

    socket
    |> assign(:slugs, slugs)
    |> assign(:unsubscribed_slugs, MapSet.new([]))
    |> assign(:metrics, metrics)
    |> assign(:unsubscribed_metrics, MapSet.new([]))
    |> assign(:sources, sources)
    |> assign(:unsubscribed_sources, MapSet.new([]))
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
