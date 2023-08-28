defmodule Sanbase.Intercom.StripeAttributes do
  require Logger

  import Ecto.Query

  alias Sanbase.Billing.Subscription
  alias Sanbase.Repo
  alias Sanbase.Billing.Subscription.Timeseries
  alias Sanbase.Accounts.User
  alias Sanbase.ClickhouseRepo
  alias Sanbase.Intercom

  def run do
    if is_prod?() do
      all_stats = all_stats()
      user_ids = fetch_all_db_user_ids()
      run(user_ids, all_stats)
    else
      :ok
    end
  end

  def run(user_ids, all_stats) do
    total = length(user_ids)

    Enum.with_index(user_ids)
    |> Enum.each(fn {user_id, index} ->
      try do
        stats = stats(all_stats, user_id)

        case Intercom.get_contact_by_user_id(user_id) do
          nil ->
            Intercom.create_contact(user_id)

          %{"id" => intercom_id, "custom_attributes" => custom_attributes} ->
            Intercom.update_contact(intercom_id, %{
              "custom_attributes" => Map.merge(custom_attributes, stats)
            })
        end

        # print progress every 100 user_ids
        if rem(index, 100) == 0 do
          progress_percent = (index + 1) / total * 100

          Logger.info(
            "stripe_attributes_intercom: Progress: Processed #{index + 1} out of #{total} user_ids (#{Float.round(progress_percent, 2)}%)"
          )
        end
      rescue
        exception ->
          Logger.error(
            "stripe_attributes_intercom: An error occurred processing user_id: #{user_id} - #{exception.message}"
          )
      end
    end)
  end

  def fetch_all_db_user_ids() do
    from(u in User, order_by: [asc: u.id], select: u.id)
    |> Repo.all()
  end

  def all_stats do
    %{
      users_with_paid_active_subscriptions: users_with_paid_active_subscriptions(),
      users_with_trialing_subscriptions: users_with_trialing_subscriptions(),
      users_renewal_upcoming_at: users_renewal_upcoming_at(),
      users_subscription_set_to_cancel: users_subscription_set_to_cancel(),
      users_last_active_at: users_last_active_at()
    }
  end

  def stats(all_stats, user_id) do
    %{
      paid_active_subscription:
        Enum.member?(all_stats[:users_with_paid_active_subscriptions], user_id),
      trialing_subscription: Enum.member?(all_stats[:users_with_trialing_subscriptions], user_id),
      renewal_upcoming_at: Map.get(all_stats[:users_renewal_upcoming_at], user_id),
      subscription_set_to_cancel:
        Enum.member?(all_stats[:users_subscription_set_to_cancel], user_id),
      last_active_at: Map.get(all_stats[:users_last_active_at], user_id)
    }
  end

  def users_with_trialing_subscriptions do
    from(
      s in Subscription,
      where: s.status == "trialing",
      select: s.user_id
    )
    |> Repo.all()
  end

  def users_with_paid_active_subscriptions() do
    stripe_customer_ids = current_active_paid_subs() |> Enum.map(& &1.customer_id)

    stripe_customer_sanbase_user_map = stripe_customer_sanbase_user_map()

    Enum.map(stripe_customer_ids, fn customer_id ->
      Map.get(stripe_customer_sanbase_user_map, customer_id)
    end)
  end

  def users_renewal_upcoming_at() do
    sub_ids = current_active_subs() |> Enum.map(& &1.id)

    from(
      s in Subscription,
      where: s.stripe_id in ^sub_ids,
      select: {s.user_id, s.current_period_end}
    )
    |> Repo.all()
    |> Enum.map(fn {user_id, current_period_end} ->
      {user_id, DateTime.to_unix(current_period_end)}
    end)
    |> Enum.into(%{})
  end

  def users_subscription_set_to_cancel() do
    sub_ids = current_active_subs() |> Enum.map(& &1.id)

    from(
      s in Subscription,
      where: s.stripe_id in ^sub_ids and s.cancel_at_period_end == true,
      select: s.user_id
    )
    |> Repo.all()
  end

  def users_last_active_at() do
    sql = """
    SELECT
      user_id,
      max(dt) as last_dt
    FROM
      api_call_data
    GROUP BY user_id
    """

    query_struct = Sanbase.Clickhouse.Query.new(sql, %{})

    ClickhouseRepo.query_transform(query_struct, fn [user_id, dt] -> {user_id, dt} end)
    |> case do
      {:ok, result} ->
        result
        |> Enum.map(fn {user_id, dt} ->
          {user_id, DateTime.from_naive!(dt, "Etc/UTC") |> DateTime.to_unix()}
        end)
        |> Enum.into(%{})

      {:error, _} ->
        %{}
    end
  end

  def stripe_customer_sanbase_user_map do
    from(
      u in User,
      where: not is_nil(u.stripe_customer_id),
      select: {u.stripe_customer_id, u.id}
    )
    |> Repo.all()
    |> Enum.into(%{})
  end

  defp current_active_subs() do
    current_subs()
    |> Timeseries.active_subscriptions()
  end

  defp current_active_paid_subs() do
    current_subs()
    |> Timeseries.active_subscriptions()
    |> Timeseries.paid()
  end

  def current_subs() do
    query = from(s in Timeseries, order_by: [desc: s.id], limit: 1)

    case Repo.one(query) do
      nil ->
        raise("No subscriptions found in subscription_timeseries")

      %Timeseries{subscriptions: subscriptions} ->
        transform_maps_to_atom_keys(subscriptions)
    end
  end

  defp transform_maps_to_atom_keys(subscriptions) do
    subscriptions
    # Transform the keys of each map from the list from string to atom.
    |> Enum.map(fn map_with_string_keys ->
      Map.new(map_with_string_keys, fn {key, value} ->
        {String.to_existing_atom(key), value}
      end)
    end)
  end

  defp is_prod?(), do: Sanbase.Utils.Config.module_get(Sanbase, :deployment_env) == "prod"
end
