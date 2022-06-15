defmodule Sanbase.Billing.StripeSync do
  import Ecto.Query

  @topic "sanbase_stripe_transactions"

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

    Sanbase.DateTimeUtils.generate_datetimes_list(
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
          plan: plan_map[transaction.plan],
          product: product_map[transaction.product]
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
      Stripe.Charge.list(params, expand: ["invoice.subscription.plan"], timeout: 30_000)

    transactions =
      res.data
      |> Enum.map(fn charge ->
        subscription = if charge.invoice, do: charge.invoice.subscription, else: nil

        {plan, product} =
          if subscription, do: {subscription.plan.id, subscription.plan.product}, else: {nil, nil}

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

  defp persist_in_kafka_async([]), do: :ok

  defp persist_in_kafka_async(transactions) do
    Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
      do_persist_sync(transactions)
    end)
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
