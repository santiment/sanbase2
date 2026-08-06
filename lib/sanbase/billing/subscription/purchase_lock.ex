defmodule Sanbase.Billing.Subscription.PurchaseLock do
  @moduledoc ~s"""
  One SanAPI new-offering purchase at a time, per user.

  ## The race this closes

  Both purchase flows for the new offering - `Bundle.Lifecycle.subscribe/2` and
  the Institutional branch of `Subscription.subscribe/4` - check that the customer
  has no live SanAPI subscription and then, some hundreds of milliseconds later,
  create one in Stripe. The check is a plain read: `classify_active_sanapi/1` runs
  `Repo.all` with no lock, because before the first purchase there is no row to
  lock.

  So two overlapping requests for the same user both see nothing, both pass, and
  both charge. `Subscription.has_active_subscriptions/2` does not help - it is the
  same unlocked read, keyed on plan id. The customer ends up with two live
  subscriptions billing in parallel at $799 or $1,050 a month, and nothing in the
  system treats that as wrong afterwards: `classify_active_sanapi/1` would refuse a
  *third*, and the hourly replacement job only cancels legacy plans.

  A double-clicked Buy button is enough.

  ## Why an advisory lock rather than a transaction or a claim row

  **Not `Repo.transaction`.** The critical section has to contain the Stripe call,
  and `Subscription.create/2` emits `:create_subscription` on the event bus.
  `BillingEventSubscriber` handles it by recomputing the customer's quota, on its
  own connection - so inside an uncommitted transaction it would read no
  subscription and write the wrong `api_call_limits` row.

  **Not post-create winner selection.** It works, but it means deliberately
  charging the customer twice and then refunding one, which is worse for them than
  being told to try again.

  **Not a claim row.** It would need a table, a unique index, and a rule for
  clearing claims left behind by a process that died mid-Stripe. An advisory lock
  is released by Postgres when the connection goes, which is the same guarantee
  without the bookkeeping.

  `pg_try_advisory_lock` is used rather than `pg_advisory_lock`: the second request
  is a double-submit, not work waiting to be done, so it should be told so
  immediately rather than queue behind an HTTP call to Stripe and then fail the
  check anyway.

  ## Connection affinity

  A session-level advisory lock belongs to the connection that took it, so the
  lock, the work and the unlock all have to run on one connection - hence
  `Repo.checkout/2`. Every query the wrapped function makes uses that same
  connection, and it is held for as long as Stripe takes to answer. That is the
  unavoidable cost of making check-and-create atomic; it is bounded by
  `@timeout`, and it applies only to purchases, which are rare.
  """

  require Logger

  alias Sanbase.Repo

  # Arbitrary but stable. Advisory locks share one namespace across the database,
  # so the first argument keeps these from colliding with any other use.
  @namespace 8412

  # Generous, because a Stripe call sits inside. If it is ever hit, the customer
  # sees a failed purchase rather than a duplicate one.
  @timeout :timer.seconds(60)

  @busy_message "A subscription purchase for this account is already in progress. " <>
                  "Please wait for it to finish before trying again."

  @doc ~s"""
  Run `fun` while holding this user's purchase lock.

  Returns whatever `fun` returns. If another request already holds the lock,
  `fun` is **not** run and `{:error, message}` is returned.

  The lock is released whether `fun` returns, raises or throws - and by Postgres
  itself if the connection dies, so a crash mid-purchase cannot leave a user
  permanently unable to buy.
  """
  @spec with_lock(pos_integer(), (-> result)) :: result | {:error, String.t()}
        when result: term()
  def with_lock(user_id, fun) when is_integer(user_id) and is_function(fun, 0) do
    Repo.checkout(
      fn ->
        if acquire(user_id) do
          try do
            fun.()
          after
            release(user_id)
          end
        else
          Logger.info(
            "[PurchaseLock] Refused a concurrent SanAPI purchase for user #{user_id} - " <>
              "another one is already in progress."
          )

          {:error, @busy_message}
        end
      end,
      timeout: @timeout
    )
  end

  @doc ~s"""
  The message a caller gets when someone else holds the lock.

  Exposed so tests can assert on it without restating it.
  """
  @spec busy_message() :: String.t()
  def busy_message, do: @busy_message

  defp acquire(user_id) do
    %{rows: [[acquired?]]} =
      Repo.query!("SELECT pg_try_advisory_lock($1, $2)", [@namespace, user_id])

    acquired?
  end

  defp release(user_id) do
    Repo.query!("SELECT pg_advisory_unlock($1, $2)", [@namespace, user_id])
    :ok
  end
end
