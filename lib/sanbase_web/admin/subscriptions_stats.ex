defmodule SanbaseWeb.Admin.SubscriptionsStats do
  @moduledoc """
  Aggregated subscription metrics for the admin subscriptions dashboard.
  Counts come from the local DB; discount info is pulled from Stripe and
  joined to local subs by `stripe_id`. Cached for `@ttl_seconds` to keep
  the page snappy and to avoid hammering Stripe.
  """

  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Billing.Subscription
  alias Sanbase.Billing.Subscription.Timeseries

  @ttl_seconds 900

  @spec get() :: {:ok, map()} | {:error, term()}
  def get do
    cache_key = {__MODULE__, :get, :v1} |> Sanbase.Cache.hash()
    Sanbase.Cache.get_or_store({cache_key, @ttl_seconds}, fn -> {:ok, compute()} end)
  end

  defp compute do
    now = DateTime.utc_now()

    parts =
      [
        overview: &overview_block/0,
        by_status: &by_status_block/0,
        by_product_plan: &by_product_plan_block/0,
        by_type: &by_type_block/0,
        internal_external: &internal_external_block/0,
        trialing: fn -> trialing_block(now) end,
        scheduled_cancellations: &scheduled_cancellations_block/0,
        recent_activity: fn -> recent_activity_block(now) end,
        discounts: &discounts_block/0
      ]
      |> Task.async_stream(
        fn {key, fun} -> {key, fun.()} end,
        max_concurrency: 8,
        timeout: 60_000,
        ordered: false
      )
      |> Enum.map(fn {:ok, kv} -> kv end)
      |> Map.new()

    Map.put(parts, :computed_at, now)
  end

  defp overview_block do
    rows =
      from(s in Subscription, group_by: s.status, select: {s.status, count()})
      |> Repo.all()
      |> Map.new()

    total = rows |> Map.values() |> Enum.sum()

    internal =
      from(s in Subscription,
        join: u in assoc(s, :user),
        where: like(u.email, "%@santiment.net")
      )
      |> Repo.aggregate(:count)

    scheduled_cancellation =
      from(s in Subscription,
        where: s.cancel_at_period_end == true and s.status in [:active, :trialing]
      )
      |> Repo.aggregate(:count)

    %{
      total: total,
      active: Map.get(rows, :active, 0),
      trialing: Map.get(rows, :trialing, 0),
      past_due: Map.get(rows, :past_due, 0),
      canceled: Map.get(rows, :canceled, 0),
      incomplete: Map.get(rows, :incomplete, 0) + Map.get(rows, :incomplete_expired, 0),
      unpaid: Map.get(rows, :unpaid, 0),
      internal: internal,
      scheduled_cancellation: scheduled_cancellation
    }
  end

  defp by_status_block do
    from(s in Subscription, group_by: s.status, select: {s.status, count()})
    |> Repo.all()
    |> Enum.map(fn {status, count} -> %{status: status, count: count} end)
    |> Enum.sort_by(&(-&1.count))
  end

  defp by_product_plan_block do
    from(s in Subscription,
      join: pl in assoc(s, :plan),
      join: pr in assoc(pl, :product),
      where: s.status in [:active, :trialing, :past_due],
      group_by: [pr.code, pl.name, s.status],
      select: %{
        product: pr.code,
        plan: pl.name,
        status: s.status,
        count: count()
      }
    )
    |> Repo.all()
    |> Enum.sort_by(fn r -> {r.product, -r.count, r.plan} end)
  end

  defp by_type_block do
    from(s in Subscription,
      where: s.status in [:active, :trialing, :past_due],
      group_by: s.type,
      select: {s.type, count()}
    )
    |> Repo.all()
    |> Enum.map(fn {type, count} -> %{type: type, count: count} end)
    |> Enum.sort_by(&(-&1.count))
  end

  defp internal_external_block do
    rows =
      from(s in Subscription,
        join: u in assoc(s, :user),
        group_by: [
          fragment("CASE WHEN ? LIKE '%@santiment.net' THEN true ELSE false END", u.email),
          s.status
        ],
        select: %{
          is_internal:
            fragment("CASE WHEN ? LIKE '%@santiment.net' THEN true ELSE false END", u.email),
          status: s.status,
          count: count()
        }
      )
      |> Repo.all()

    {internal_rows, external_rows} = Enum.split_with(rows, & &1.is_internal)

    %{
      internal: %{
        total: Enum.reduce(internal_rows, 0, &(&1.count + &2)),
        by_status: Enum.map(internal_rows, &Map.take(&1, [:status, :count]))
      },
      external: %{
        total: Enum.reduce(external_rows, 0, &(&1.count + &2)),
        by_status: Enum.map(external_rows, &Map.take(&1, [:status, :count]))
      }
    }
  end

  defp trialing_block(now) do
    in_3d = DateTime.add(now, 3, :day)
    in_7d = DateTime.add(now, 7, :day)

    by_plan =
      from(s in Subscription,
        join: pl in assoc(s, :plan),
        join: pr in assoc(pl, :product),
        where: s.status == :trialing,
        group_by: [pr.code, pl.name],
        select: %{product: pr.code, plan: pl.name, count: count()}
      )
      |> Repo.all()
      |> Enum.sort_by(&{&1.product, -&1.count})

    total = Enum.reduce(by_plan, 0, &(&1.count + &2))

    ending_3d =
      from(s in Subscription,
        where:
          s.status == :trialing and not is_nil(s.trial_end) and
            s.trial_end >= ^now and s.trial_end <= ^in_3d
      )
      |> Repo.aggregate(:count)

    ending_7d =
      from(s in Subscription,
        where:
          s.status == :trialing and not is_nil(s.trial_end) and
            s.trial_end >= ^now and s.trial_end <= ^in_7d
      )
      |> Repo.aggregate(:count)

    %{total: total, by_plan: by_plan, ending_3d: ending_3d, ending_7d: ending_7d}
  end

  defp scheduled_cancellations_block do
    by_plan =
      from(s in Subscription,
        join: pl in assoc(s, :plan),
        join: pr in assoc(pl, :product),
        where: s.cancel_at_period_end == true and s.status in [:active, :trialing],
        group_by: [pr.code, pl.name],
        select: %{product: pr.code, plan: pl.name, count: count()}
      )
      |> Repo.all()
      |> Enum.sort_by(&{&1.product, -&1.count})

    %{total: Enum.reduce(by_plan, 0, &(&1.count + &2)), by_plan: by_plan}
  end

  defp recent_activity_block(now) do
    day_7 = DateTime.add(now, -7, :day)
    day_30 = DateTime.add(now, -30, :day)

    created_7d =
      from(s in Subscription, where: s.inserted_at >= ^day_7)
      |> Repo.aggregate(:count)

    created_30d =
      from(s in Subscription, where: s.inserted_at >= ^day_30)
      |> Repo.aggregate(:count)

    canceled_7d =
      from(s in Subscription,
        where: s.status == :canceled and s.updated_at >= ^day_7
      )
      |> Repo.aggregate(:count)

    canceled_30d =
      from(s in Subscription,
        where: s.status == :canceled and s.updated_at >= ^day_30
      )
      |> Repo.aggregate(:count)

    created_by_plan_30d =
      from(s in Subscription,
        join: pl in assoc(s, :plan),
        join: pr in assoc(pl, :product),
        where: s.inserted_at >= ^day_30,
        group_by: [pr.code, pl.name],
        select: %{product: pr.code, plan: pl.name, count: count()}
      )
      |> Repo.all()
      |> Enum.sort_by(&{&1.product, -&1.count})

    %{
      created_7d: created_7d,
      created_30d: created_30d,
      canceled_7d: canceled_7d,
      canceled_30d: canceled_30d,
      created_by_plan_30d: created_by_plan_30d
    }
  end

  defp discounts_block do
    try do
      stripe_subs = Timeseries.list_active_subs()
      stripe_with_discount = Enum.filter(stripe_subs, &(not is_nil(&1.discount)))
      stripe_map = Map.new(stripe_with_discount, fn s -> {s.id, s.discount} end)

      local_rows =
        from(s in Subscription,
          join: u in assoc(s, :user),
          join: pl in assoc(s, :plan),
          join: pr in assoc(pl, :product),
          where: not is_nil(s.stripe_id),
          select: %{
            stripe_id: s.stripe_id,
            email: u.email,
            plan_name: pl.name,
            product_code: pr.code,
            status: s.status
          }
        )
        |> Repo.all()

      local_set = MapSet.new(local_rows, & &1.stripe_id)
      stripe_set = Map.keys(stripe_map) |> MapSet.new()

      merged =
        Enum.flat_map(local_rows, fn row ->
          case Map.get(stripe_map, row.stripe_id) do
            nil -> []
            discount -> [Map.put(row, :discount, discount)]
          end
        end)

      total = length(merged)

      by_product =
        merged
        |> Enum.group_by(& &1.product_code)
        |> Enum.into(%{}, fn {k, v} -> {k, length(v)} end)

      by_plan =
        merged
        |> Enum.group_by(fn r -> {r.product_code, r.plan_name} end)
        |> Enum.map(fn {{prod, plan}, rows} ->
          %{product: prod, plan: plan, count: length(rows)}
        end)
        |> Enum.sort_by(&{&1.product, -&1.count})

      histogram =
        merged
        |> Enum.frequencies_by(& &1.discount.percent_off)
        |> Enum.sort_by(fn {k, _} -> -(k || 0) end)
        |> Enum.map(fn {k, v} -> %{percent_off: k, count: v} end)

      top_coupons =
        merged
        |> Enum.frequencies_by(fn r ->
          {r.discount.coupon_id, r.discount.coupon_name, r.discount.percent_off}
        end)
        |> Enum.sort_by(fn {_k, v} -> -v end)
        |> Enum.take(10)
        |> Enum.map(fn {{id, name, pct}, count} ->
          %{coupon_id: id, coupon_name: name, percent_off: pct, count: count}
        end)

      now = DateTime.utc_now()
      cutoff_30d = DateTime.add(now, 30, :day)

      expiring_30d =
        Enum.count(merged, fn r ->
          case r.discount.end do
            %DateTime{} = dt ->
              DateTime.compare(dt, now) == :gt and DateTime.compare(dt, cutoff_30d) != :gt

            _ ->
              false
          end
        end)

      internal_count = Enum.count(merged, &internal_email?/1)
      external_count = total - internal_count

      drift_local_only = MapSet.difference(local_set, stripe_set) |> MapSet.size()
      drift_stripe_only = MapSet.difference(stripe_set, local_set) |> MapSet.size()

      {:ok,
       %{
         total: total,
         total_stripe_active: length(stripe_subs),
         by_product: by_product,
         by_plan: by_plan,
         histogram: histogram,
         top_coupons: top_coupons,
         expiring_30d: expiring_30d,
         internal_count: internal_count,
         external_count: external_count,
         drift_local_only: drift_local_only,
         drift_stripe_only: drift_stripe_only
       }}
    rescue
      e -> {:error, Exception.message(e)}
    catch
      kind, value -> {:error, "#{kind}: #{inspect(value)}"}
    end
  end

  defp internal_email?(%{email: nil}), do: false
  defp internal_email?(%{email: email}), do: String.ends_with?(email, "@santiment.net")
end
