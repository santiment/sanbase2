defmodule Sanbase.Billing.StripeSync do
  import Ecto.Query

  @topic "stripe_transactions"

  def fetch_all_transactions() do
    cust_map = stripe_customer_user_id_map()
    to = Timex.now()
    from = Timex.shift(to, days: -1)

    transactions(from, to)
    |> Enum.map(fn transaction ->
      %{
        user_id: cust_map[transaction.customer],
        timestamp: transaction.created_at,
        data: %{
          id: transaction.id,
          status: transaction.status,
          amount: transaction.amount,
          plan: plan_map[transaction.plan],
          product: product_map[transaction.product]
        }
      }
    end)
  end

  def transactions(from, to, starting_after \\ nil) do
    from_ux = from |> DateTime.to_unix()
    to_ux = to |> DateTime.to_unix()

    params = %{
      created: %{gte: from_ux, lt: to_ux},
      limit: 100
    }

    params =
      if starting_after do
        Map.put(params, :starting_after, starting_after)
      else
        params
      end

    {:ok, res} = Stripe.Charge.list(params, expand: ["invoice.subscription.plan"])

    transactions =
      res.data
      # |> Enum.filter(fn charge -> charge.status == "succeeded" end)
      |> Enum.map(fn charge ->
        %{
          id: charge.id,
          status: charge.status,
          created_at: charge.created,
          amount: charge.amount / 100,
          customer: charge.customer,
          plan: charge.invoice.subscription.plan.id,
          product: charge.invoice.subscription.plan.product
        }
      end)

    if res.has_more do
      starting_after = List.last(res.data) |> Map.get(:id)
      transactions ++ transactions(from, to, starting_after)
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
      timestamp = DateTime.to_unix(transaction.timestamp)
      key = "#{transaction.user_id}_#{timestamp}"

      {key, Jason.encode!(transaction)}
    end)
  end
end
