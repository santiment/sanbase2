defmodule Sanbase.ApiCallLimit.Sync do
  @moduledoc """
  Force an update of the stored subscription plans for users in the api call limit table.

  When a subscription changes, the ApiCallLimit.update_user_plan/1 function must be
  explicitly invoked, otherwise the old api plan restrictions could still apply.

  The event-driven path (BillingEventSubscriber) handles real-time changes; this
  daily job is a safety net. It bulk-compares all active subscriptions against ACL
  records (2 queries) and only calls update_user_plan for actual mismatches:

  - Stale: ACL says paid but user has no active subscription
  - Missing: user has an active subscription but ACL says free
  - Wrong plan: both exist but plan name doesn't match
  """
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.ApiCallLimit
  alias Sanbase.Billing.Subscription
  alias Sanbase.Billing.Product
  alias Sanbase.Accounts.User

  require Logger

  @product_api_id Product.product_api()
  @product_sanbase_id Product.product_sanbase()

  def run() do
    # 1 query: expected plan for every user with an active subscription
    expected = expected_plans_bulk()
    subscribed_ids = Map.keys(expected) |> MapSet.new()

    # 1 query: actual plan for every user with a non-free ACL record
    actual = non_free_acl_plans()
    paid_acl_ids = Map.keys(actual) |> MapSet.new()

    # Stale: ACL says paid but user has no active subscription
    stale_ids = MapSet.difference(paid_acl_ids, subscribed_ids)

    # Missing: user has subscription but ACL says free (not in non-free map)
    missing_ids = MapSet.difference(subscribed_ids, paid_acl_ids)

    # Wrong plan: both exist but plan name doesn't match
    both_ids = MapSet.intersection(subscribed_ids, paid_acl_ids)

    wrong_plan_ids =
      Enum.filter(both_ids, fn uid ->
        {expected_plan, _status} = expected[uid]
        actual[uid] != expected_plan
      end)
      |> MapSet.new()

    user_ids_to_sync =
      stale_ids
      |> MapSet.union(missing_ids)
      |> MapSet.union(wrong_plan_ids)
      |> MapSet.to_list()

    Logger.info(
      "ApiCallLimit.Sync: " <>
        "#{MapSet.size(stale_ids)} stale, " <>
        "#{MapSet.size(missing_ids)} missing, " <>
        "#{MapSet.size(wrong_plan_ids)} wrong plan. " <>
        "Syncing #{length(user_ids_to_sync)} users."
    )

    sync_user_ids(user_ids_to_sync)

    :ok
  end

  @doc false
  def expected_plans_bulk do
    from(s in Subscription,
      where: s.status in [:active, :past_due, :trialing],
      join: p in assoc(s, :plan),
      join: prod in assoc(p, :product),
      preload: [plan: {p, product: prod}],
      order_by: [desc: s.id]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.user_id)
    |> Map.new(fn {user_id, subs} ->
      # Match user_to_plan priority: API product first, then Sanbase
      sub =
        Enum.find(subs, &(&1.plan.product_id == @product_api_id)) ||
          Enum.find(subs, &(&1.plan.product_id == @product_sanbase_id)) ||
          hd(subs)

      plan_name = ApiCallLimit.subscription_to_plan_name(sub)
      {user_id, {plan_name, to_string(sub.status)}}
    end)
  end

  defp non_free_acl_plans do
    from(acl in ApiCallLimit,
      where: not is_nil(acl.user_id) and acl.api_calls_limit_plan != "sanapi_free",
      select: {acl.user_id, acl.api_calls_limit_plan}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp sync_user_ids([]) do
    Logger.info("ApiCallLimit.Sync: no mismatches found, nothing to reconcile.")
  end

  defp sync_user_ids(user_ids) do
    users =
      from(u in User, where: u.id in ^user_ids)
      |> Repo.all()

    results =
      Sanbase.TaskSupervisor
      |> Task.Supervisor.async_stream(
        users,
        fn user -> ApiCallLimit.update_user_plan(user) end,
        timeout: :infinity,
        max_concurrency: 2
      )
      |> Enum.reduce(%{ok: 0, error: 0}, fn
        {:ok, {:ok, _}}, acc ->
          %{acc | ok: acc.ok + 1}

        {:ok, {:error, _}}, acc ->
          %{acc | error: acc.error + 1}

        {:exit, reason}, acc ->
          Logger.error("Failed to update plan in sync: #{inspect(reason)}")
          %{acc | error: acc.error + 1}
      end)

    Logger.info(
      "ApiCallLimit.Sync: reconciled #{results.ok + results.error} users. " <>
        "Success: #{results.ok}, Errors: #{results.error}"
    )
  end
end
