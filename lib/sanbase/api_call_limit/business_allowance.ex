defmodule Sanbase.ApiCallLimit.BusinessAllowance do
  @moduledoc ~s"""
  The reduced monthly API call allowance of SanAPI `BUSINESS_PRO` and
  `BUSINESS_MAX`, and the grandfathering of everyone who subscribed before it.

  ## Who gets what

  A Business subscription created (in Stripe) on or after the cutoff gets the
  reduced monthly allowance from
  `Sanbase.ApiCallLimit.Restrictions.reduced_business_call_limits_per_month/0`.
  Every subscription created before it keeps the allowance in
  `Sanbase.ApiCallLimit.Restrictions.call_limits_per_month/0`, which is left
  unchanged on purpose. Only the monthly figure moves: hour and minute are burst
  protection and stay as the plan has them.

  The subscription's `inserted_at` is what is compared. A subscription synced from
  Stripe takes it from the Stripe creation time, so it does not move when a row is
  re-synced, and a plan change on the same Stripe subscription (PRO to MAX, monthly
  to yearly) keeps the customer on the side of the cutoff they started on. A
  customer who cancels and subscribes again gets a new subscription, and so the
  reduced allowance.

  ## Why the old numbers stay the default

  The plan tables keep the old figures and only new subscriptions store the reduced
  one on their `api_call_limits` row (`resolved_api_call_limits` with
  `"exact_month" => true`). The reverse - lowering the tables and storing the old
  figure for every existing customer - would throttle every paying customer whose
  row had not been rewritten yet, from the moment of the deploy. This way, a row
  that has not been refreshed, a failed refresh or a missing cutoff all err towards
  the old, larger allowance: the worst case is a new customer getting more calls
  than they bought, never an existing customer getting fewer.

  It also means there is nothing to backfill and no deploy ordering to get right.

  ## The cutoff

  The `business_reduced_api_calls` feature toggle (Admin → Feature Toggles, or
  `enable/0` and `disable/0` from IEx). The moment it is turned on is the cutoff,
  stored in the toggle's `enabled_at`. Off means the reduction is off and every
  Business subscription keeps the old allowance.

  Because "on" always means "from now", the cutoff can never be put in the past,
  which is the one edit that would move existing customers onto the reduced
  allowance. Turning it off and on again moves the cutoff later, which only ever
  grandfathers more customers.

  Turning it off refreshes every row on the reduced allowance (`refresh_reduced/0`),
  so those customers go back to the old one without waiting for their next
  subscription event. `disable/0` does that, and so does the admin page. Turning it
  on runs the same refresh: a row a failed refresh left on the reduced allowance
  belongs to a subscription from before the new cutoff, so it is grandfathered now.

  The refresh rewrites the rows in the database and clears the quota cached on the
  node that runs it. Other API nodes keep the quota they cached until it reloads
  from the database, so the change reaches them shortly after, not at the same
  instant.

  Only change the toggle through those two. An `UPDATE` in SQL neither stamps nor
  clears `enabled_at` and does not run the refresh.
  """

  import Ecto.Query

  alias Sanbase.Accounts.User
  alias Sanbase.ApiCallLimit
  alias Sanbase.ApiCallLimit.Restrictions
  alias Sanbase.Billing.Subscription
  alias Sanbase.FeatureToggle
  alias Sanbase.Repo

  require Logger

  # Advisory locks share one namespace across the database; 8412 and 8413 are taken by
  # the purchase lock and the invoice mirror sync.
  @lock_namespace 8414
  @lock_key 1

  @doc ~s"""
  The cutoff as a `NaiveDateTime`, or `nil` when the reduction is off.
  """
  @spec cutoff() :: NaiveDateTime.t() | nil
  def cutoff do
    case FeatureToggle.business_reduced_api_calls_since() do
      %DateTime{} = dt -> DateTime.to_naive(dt)
      _ -> nil
    end
  end

  @type refresh_result ::
          %{refreshed: non_neg_integer(), failed: [integer()]} | {:error, String.t()}

  @doc ~s"""
  Turn the reduction on. The cutoff is now.

  Also refreshes any row still on the reduced allowance from before (one a failed
  refresh left behind when it was last turned off): its subscription predates the new
  cutoff, so it goes back to the old allowance.
  """
  @spec enable() :: {:ok, %FeatureToggle{}, refresh_result()} | {:error, Ecto.Changeset.t()}
  def enable() do
    with {:ok, toggle} <- FeatureToggle.enable_business_reduced_api_calls() do
      {:ok, toggle, refresh_reduced()}
    end
  end

  @doc ~s"""
  Turn the reduction off and put every customer on the reduced allowance back on
  the old one.
  """
  @spec disable() :: {:ok, %FeatureToggle{}, refresh_result()} | {:error, Ecto.Changeset.t()}
  def disable() do
    with {:ok, toggle} <- FeatureToggle.disable_business_reduced_api_calls() do
      {:ok, toggle, refresh_reduced()}
    end
  end

  @doc ~s"""
  Recompute the limits of every user whose row is on the reduced allowance. With the
  toggle off, that removes the reduction from all of them.

  Returns how many were refreshed and the ids of those that failed. A failure is
  logged and leaves that row on the reduced allowance until its next subscription
  event, so it is worth re-running. If it cannot first wait for the plan updates in
  flight, nothing is refreshed and it returns `{:error, message}`.
  """
  @spec refresh_reduced() :: refresh_result()
  def refresh_reduced() do
    case wait_for_plan_updates() do
      :ok -> refresh_reduced_rows()
      {:error, _} = error -> error
    end
  end

  defp refresh_reduced_rows() do
    user_ids =
      from(acl in ApiCallLimit,
        where:
          not is_nil(acl.user_id) and
            fragment("(?->>'exact_month') = 'true'", acl.resolved_api_call_limits),
        select: acl.user_id
      )
      |> Repo.all()

    from(u in User, where: u.id in ^user_ids)
    |> Repo.all()
    |> Enum.reduce(%{refreshed: 0, failed: []}, fn user, acc ->
      case refresh_user(user) do
        {:ok, _} ->
          %{acc | refreshed: acc.refreshed + 1}

        error ->
          Logger.error(
            "[BusinessAllowance] Could not refresh the API call limits of user #{user.id}: #{inspect(error)}"
          )

          %{acc | failed: [user.id | acc.failed]}
      end
    end)
  end

  # One customer's failure must not stop the rest from being refreshed.
  defp refresh_user(user) do
    ApiCallLimit.update_user_plan(user)
  rescue
    exception -> {:error, exception}
  end

  @doc ~s"""
  Taken (shared) by `Sanbase.ApiCallLimit.update_user_plan/1` inside its transaction,
  before it reads the plan state and until it writes the row. Must be called inside a
  transaction; it is released at the commit.
  """
  @spec lock_for_plan_update() :: :ok
  def lock_for_plan_update() do
    Repo.query!("SELECT pg_advisory_xact_lock_shared($1, $2)", [@lock_namespace, @lock_key])
    :ok
  end

  # Takes the lock exclusively and lets go of it at once: that returns only after every
  # plan update in flight has committed. Called after the toggle is turned off, every
  # update that could still have read it as on has then written its row, so the query
  # that follows finds it, and every later update reads the toggle as off.
  defp wait_for_plan_updates() do
    {:ok, _} =
      Repo.transaction(fn ->
        Repo.query!("SELECT pg_advisory_xact_lock($1, $2)", [@lock_namespace, @lock_key])
      end)

    :ok
  rescue
    exception ->
      Logger.error(
        "[BusinessAllowance] Could not wait for in-flight plan updates: #{Exception.message(exception)}"
      )

      {:error,
       "could not wait for in-flight API call limit updates, so no customer was refreshed; " <>
         "run the refresh again"}
  end

  @doc ~s"""
  Whether new Business subscriptions get the reduced allowance right now - the
  cutoff is set and has passed. This is what the plan catalog shows.
  """
  @spec active?() :: boolean()
  def active? do
    case cutoff() do
      nil -> false
      cutoff -> NaiveDateTime.compare(NaiveDateTime.utc_now(), cutoff) != :lt
    end
  end

  @doc ~s"""
  Whether `plan_key` (an `api_call_limits.api_calls_limit_plan` value such as
  `"sanapi_business_pro"`) is one the reduction applies to.
  """
  @spec reducible_plan?(term()) :: boolean()
  def reducible_plan?(plan_key),
    do: Map.has_key?(Restrictions.reduced_business_call_limits_per_month(), plan_key)

  @doc ~s"""
  Whether this subscription is on the reduced allowance: a reducible plan, created
  on or after the cutoff.
  """
  @spec reduced?(Subscription.t(), String.t()) :: boolean()
  def reduced?(%Subscription{inserted_at: %NaiveDateTime{} = inserted_at}, plan_key) do
    with true <- reducible_plan?(plan_key),
         %NaiveDateTime{} = cutoff <- cutoff() do
      NaiveDateTime.compare(inserted_at, cutoff) != :lt
    else
      _ -> false
    end
  end

  def reduced?(_subscription, _plan_key), do: false

  @doc ~s"""
  The reduced monthly allowance of `plan_key`, or `nil` when it has none.
  """
  @spec reduced_month(String.t()) :: pos_integer() | nil
  def reduced_month(plan_key), do: Restrictions.reduced_business_call_limits_per_month()[plan_key]
end
