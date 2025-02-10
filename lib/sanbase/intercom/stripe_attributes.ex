defmodule Sanbase.Intercom.StripeAttributes do
  @moduledoc false
  import Ecto.Query

  alias Sanbase.Accounts.User
  alias Sanbase.Billing.Subscription
  alias Sanbase.Billing.Subscription.Timeseries
  alias Sanbase.Intercom
  alias Sanbase.Repo

  require Logger

  def run do
    if prod?() do
      all_stats = all_stats()

      user_ids = Enum.uniq(get_distinct_user_ids_updated_in_last_5_months() ++ get_all_user_ids_from_stats(all_stats))

      run(user_ids, all_stats)
    else
      :ok
    end
  end

  def run(user_ids, all_stats) do
    total = length(user_ids)

    user_ids
    |> Enum.with_index()
    |> Enum.each(fn {user_id, index} ->
      try do
        stats = stats(all_stats, user_id)

        case Intercom.get_contact_by_user_id(user_id) do
          nil ->
            Intercom.create_contact(user_id)

          %{"id" => intercom_id, "custom_attributes" => custom_attributes} ->
            params = %{"custom_attributes" => Map.merge(custom_attributes, stats)}
            Intercom.update_contact(intercom_id, params)
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
            "stripe_attributes_intercom: An error occurred processing user_id: #{user_id} - #{Exception.message(exception)}"
          )
      end
    end)
  end

  def all_stats do
    %{
      users_with_paid_active_subscriptions: users_with_paid_active_subscriptions(),
      users_with_trialing_subscriptions: users_with_trialing_subscriptions(),
      users_renewal_upcoming_at: users_renewal_upcoming_at(),
      users_subscription_set_to_cancel: users_subscription_set_to_cancel()
    }
  end

  def stats(all_stats, user_id) do
    %{
      "paid_active_subscription" => Enum.member?(all_stats[:users_with_paid_active_subscriptions], user_id),
      "trialing_subscription" => Enum.member?(all_stats[:users_with_trialing_subscriptions], user_id),
      "renewal_upcoming_at" => Map.get(all_stats[:users_renewal_upcoming_at], user_id),
      "subscription_set_to_cancel" => Enum.member?(all_stats[:users_subscription_set_to_cancel], user_id)
    }
  end

  def users_with_trialing_subscriptions do
    Repo.all(from(s in Subscription, where: s.status == "trialing", select: s.user_id))
  end

  def users_with_paid_active_subscriptions do
    stripe_customer_ids = Enum.map(current_active_paid_subs(), & &1.customer_id)

    stripe_customer_sanbase_user_map = stripe_customer_sanbase_user_map()

    Enum.map(stripe_customer_ids, fn customer_id ->
      Map.get(stripe_customer_sanbase_user_map, customer_id)
    end)
  end

  def users_renewal_upcoming_at do
    sub_ids = Enum.map(current_active_subs(), & &1.id)

    from(
      s in Subscription,
      where: s.stripe_id in ^sub_ids,
      select: {s.user_id, s.current_period_end}
    )
    |> Repo.all()
    |> Map.new(fn {user_id, current_period_end} ->
      {user_id, DateTime.to_unix(current_period_end)}
    end)
  end

  def users_subscription_set_to_cancel do
    sub_ids = Enum.map(current_active_subs(), & &1.id)

    Repo.all(
      from(s in Subscription, where: s.stripe_id in ^sub_ids and s.cancel_at_period_end == true, select: s.user_id)
    )
  end

  def get_distinct_user_ids_updated_in_last_5_months do
    Repo.all(from(s in Subscription, where: s.updated_at >= ago(5, "month"), select: s.user_id, distinct: s.user_id))
  end

  def stripe_customer_sanbase_user_map do
    from(
      u in User,
      where: not is_nil(u.stripe_customer_id),
      select: {u.stripe_customer_id, u.id}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp current_active_subs do
    Timeseries.active_subscriptions(current_subs())
  end

  defp current_active_paid_subs do
    current_subs()
    |> Timeseries.active_subscriptions()
    |> Timeseries.paid()
  end

  defp current_subs do
    query = from(s in Timeseries, order_by: [desc: s.id], limit: 1)

    case Repo.one(query) do
      nil ->
        raise("No subscriptions found in subscription_timeseries")

      %Timeseries{subscriptions: subscriptions} ->
        transform_maps_to_atom_keys(subscriptions)
    end
  end

  def get_all_user_ids_from_stats(all_stats) do
    keys = Map.keys(all_stats)

    keys
    |> Enum.reduce([], fn key, acc ->
      case Map.get(all_stats, key) do
        %{} ->
          Enum.concat(acc, Map.keys(Map.get(all_stats, key)))

        _ ->
          Enum.concat(acc, Map.get(all_stats, key))
      end
    end)
    |> Enum.uniq()
  end

  defp transform_maps_to_atom_keys(subscriptions) do
    # Transform the keys of each map from the list from string to atom.
    Enum.map(subscriptions, fn map_with_string_keys ->
      Map.new(map_with_string_keys, fn {key, value} ->
        {String.to_existing_atom(key), value}
      end)
    end)
  end

  defp prod?, do: Sanbase.Utils.Config.module_get(Sanbase, :deployment_env) == "prod"
end
