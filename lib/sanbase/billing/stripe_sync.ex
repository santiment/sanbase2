defmodule Sanbase.Billing.StripeSync do
  import Ecto.Query

  @topic "sanbase_stripe_transactions"

  # A charge against a subscription with more than one item pays for all of them
  # at once, so no single price id describes it and no `plans` row can name it -
  # package prices deliberately live in their own catalog. Emitting one item's id
  # would silently attribute the whole amount to that package, so emit something
  # that is obviously not a stripe id and can be grepped for instead.
  @multi_item_marker "MULTI_ITEM_SUBSCRIPTION"

  def run do
    if not localhost_or_stage?() do
      start_dt = Timex.now() |> Timex.beginning_of_day()

      sync_all_transactions(start_dt)
    end

    :ok
  end

  def sync_all_transactions(start_dt) do
    cust_map = stripe_customer_user_id_map()
    plan_map = plan_map()
    product_map = product_map()

    Sanbase.Utils.DateTime.generate_datetimes_list(
      start_dt,
      "1d",
      Timex.diff(Timex.now(), start_dt, :days)
    )
    |> Enum.each(fn dt ->
      from = Timex.beginning_of_day(dt) |> DateTime.to_unix()
      to = Timex.end_of_day(dt) |> DateTime.to_unix()
      params = %{created: %{gte: from, lt: to}}

      transactions(params)
      |> Enum.map(fn transaction ->
        data = %{
          id: transaction.id,
          status: transaction.status,
          amount: transaction.amount,
          plan: resolve_name(plan_map, transaction.plan),
          product: resolve_name(product_map, transaction.product)
        }

        %{
          user_id: cust_map[transaction.customer],
          timestamp: transaction.created_at,
          data: Jason.encode!(data),
          id: transaction.id
        }
      end)
      |> do_persist_sync()
    end)
  end

  def transactions(params \\ %{}) do
    # %{created: %{gte: from_ux, lt: to_ux}}
    params = %{limit: 10} |> Map.merge(params)

    {:ok, res} =
      Stripe.Charge.list(params, expand: ["data.invoice.subscription.plan"], timeout: 30_000)

    transactions =
      res.data
      |> Enum.map(fn charge ->
        subscription = if charge.invoice, do: charge.invoice.subscription, else: nil

        {plan, product} = plan_and_product(subscription)

        %{
          id: charge.id,
          status: charge.status,
          created_at: charge.created,
          amount: charge.amount / 100,
          customer: charge.customer,
          plan: plan,
          product: product
        }
      end)

    if res.has_more do
      id = List.last(res.data) |> Map.get(:id)
      transactions ++ transactions(Map.merge(params, %{starting_after: id}))
    else
      transactions
    end
  end

  # An unexpanded or missing subscription leaves the charge unattributed rather
  # than raising and taking the whole sync run down.
  defp plan_and_product(%{items: %{data: items}}), do: items_plan_and_product(items)
  defp plan_and_product(_), do: {nil, nil}

  defp items_plan_and_product([item]), do: {item_field(item, :id), item_field(item, :product)}
  defp items_plan_and_product([_ | _]), do: {@multi_item_marker, @multi_item_marker}
  defp items_plan_and_product(_), do: {nil, nil}

  # A Price-based item carries no legacy `plan` object. For the items that do
  # carry one its id is the same as the price id, so preferring `plan` keeps the
  # output for legacy subscriptions byte for byte what it was.
  defp item_field(item, field) do
    case Map.get(item, :plan) || Map.get(item, :price) do
      nil -> nil
      plan_or_price -> Map.get(plan_or_price, field)
    end
  end

  # The marker is not a stripe id, so it must skip the id -> name lookup that
  # would otherwise turn it into nil and lose the signal.
  defp resolve_name(_map, @multi_item_marker), do: @multi_item_marker
  defp resolve_name(map, stripe_id), do: map[stripe_id]

  def stripe_customer_user_id_map do
    from(u in Sanbase.Accounts.User,
      where: not is_nil(u.stripe_customer_id),
      select: %{u.stripe_customer_id => u.id}
    )
    |> Sanbase.Repo.all()
    |> Enum.reduce(%{}, fn x, acc -> Map.merge(acc, x) end)
  end

  def plan_map do
    from(p in Sanbase.Billing.Plan, select: %{p.stripe_id => p.name})
    |> Sanbase.Repo.all()
    |> Enum.reduce(%{}, fn x, acc -> Map.merge(acc, x) end)
  end

  def product_map do
    from(p in Sanbase.Billing.Product, select: %{p.stripe_id => p.name})
    |> Sanbase.Repo.all()
    |> Enum.reduce(%{}, fn x, acc -> Map.merge(acc, x) end)
  end

  defp do_persist_sync(transactions) do
    transactions
    |> Enum.chunk_every(100)
    |> Enum.each(fn transactions ->
      Sanbase.KafkaExporter.send_data_to_topic_from_current_process(
        to_json_kv_tuple(transactions),
        @topic
      )
    end)
  end

  defp to_json_kv_tuple(transactions) do
    transactions
    |> Enum.map(fn transaction ->
      key = transaction.id
      transaction = Map.delete(transaction, :id)
      {key, Jason.encode!(transaction)}
    end)
  end

  defp localhost_or_stage? do
    frontend_url = SanbaseWeb.Endpoint.frontend_url()

    is_binary(frontend_url) &&
      String.contains?(frontend_url, ["stage", "localhost"])
  end
end
