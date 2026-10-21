defmodule Sanbase.Billing.InvoiceMirror.Sync do
  @moduledoc ~s"""
  Imports every Stripe invoice and its lines into the local mirror.

  Every invoice except drafts is kept, with its status: paid, open, uncollectible and
  void alike, so the readers decide what counts as revenue. Invoices are upserted by
  their Stripe id and the lines of each imported invoice are replaced as a whole, so
  importing the same range twice is harmless and a later run picks up a status that
  changed in the meantime.

  Nothing is pruned: Stripe never deletes a finalized invoice, voiding one is a status.

  Unlike `Sanbase.Billing.CreditPayments.Sync`, a Stripe error fails the whole run
  instead of importing what was fetched before it. A partial import would look like
  a range with less revenue; a failed run is recorded and leaves the range a visible
  gap.

  A daily run keeps the recent past fresh; the admin panel triggers wider ranges by
  hand through `Sanbase.Billing.InvoiceMirror.SyncJob`.
  """

  import Ecto.Query

  alias Sanbase.Accounts.User
  alias Sanbase.Billing.CreditPayments
  alias Sanbase.Billing.InvoiceMirror.{Invoice, InvoiceLine, SyncRun}
  alias Sanbase.Billing.Plan
  alias Sanbase.Repo

  require Logger

  @default_recent_days 7
  @page_size 100
  @chunk_size 500
  @max_range_years 3

  # How far back an invoice still open or uncollectible is fetched again by the daily
  # run. Past that, a net-30 wire or a card retry has long settled one way or another.
  @refresh_days 400
  @unsettled_statuses ["open", "uncollectible"]

  # A run still marked running this long after it started died with its node.
  @stale_after_hours 6

  # Arbitrary but stable, and distinct from `Sanbase.Billing.Subscription.PurchaseLock`.
  # The two-key form keeps it out of the single-key advisory lock space.
  @lock_namespace 8413
  @lock_key 1

  @doc ~s"""
  Imports the last `days` days, the daily scheduled entry point.

  The window overlaps itself on purpose: an invoice paid, voided or marked
  uncollectible days after it was issued is picked up by the next run. Older invoices
  still open or uncollectible - a net-30 wire marked paid weeks later, a card paid on
  a late retry - are fetched again one by one, back to #{@refresh_days} days.
  """
  @spec run(non_neg_integer()) :: {:ok, map()} | {:error, any()}
  def run(days \\ @default_recent_days) do
    today = Date.utc_today()

    sync_range(Date.add(today, -days), today, refresh_unsettled: true)
  end

  @doc ~s"""
  Imports the invoices created in one date range, recording the run so the coverage
  stays auditable.

  One import runs at a time across all nodes, held by a Postgres advisory lock: the
  scheduled run and one started from the admin panel would otherwise replace the same
  invoices' lines at once. When another import holds the lock this returns
  `{:error, :already_running}` and records nothing. A range that ends before it starts
  or spans more than #{@max_range_years} years is refused the same way.

  `opts` accepts `:triggered_by` (a user id), `:refresh_unsettled` (also fetch again
  the older open and uncollectible invoices, see `run/1`) and `:on_progress`, a one
  argument function called with `{:run, %SyncRun{}}` once the run is recorded and with
  `{:phase, atom}` as the import moves along.
  """
  @spec sync_range(Date.t(), Date.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def sync_range(%Date{} = from_date, %Date{} = to_date, opts \\ []) do
    with :ok <- validate_range(from_date, to_date) do
      with_lock(fn -> locked_sync_range(from_date, to_date, opts) end)
    end
  end

  defp validate_range(from_date, to_date) do
    cond do
      Date.compare(from_date, to_date) == :gt ->
        {:error, "The start date must not be after the end date"}

      Date.compare(to_date, Date.shift(from_date, year: @max_range_years)) == :gt ->
        {:error, "Import at most #{@max_range_years} years at a time"}

      true ->
        :ok
    end
  end

  defp locked_sync_range(from_date, to_date, opts) do
    started_at = System.monotonic_time(:millisecond)
    on_progress = Keyword.get(opts, :on_progress, fn _event -> :ok end)

    # Holding the lock means no other import is running, so a row still marked running
    # belongs to one that died.
    SyncRun.interrupt_stale(@stale_after_hours)

    {:ok, run} =
      SyncRun.create(%{
        from_date: from_date,
        to_date: to_date,
        status: "running",
        triggered_by: Keyword.get(opts, :triggered_by)
      })

    on_progress.({:run, run})

    try do
      summary = import_range(from_date, to_date, on_progress)

      summary =
        if Keyword.get(opts, :refresh_unsettled, false),
          do: Map.put(summary, :refresh, refresh_unsettled(from_date)),
          else: summary

      backfill_plan_ids()

      {:ok, run} =
        SyncRun.update(run, %{
          status: "completed",
          invoices_upserted: summary.invoices_upserted,
          lines_upserted: summary.lines_upserted,
          duration_ms: elapsed(started_at)
        })

      on_progress.({:phase, :done})

      {:ok, Map.put(summary, :run, run)}
    rescue
      e ->
        message = Exception.message(e)
        Logger.error("InvoiceMirror.Sync failed for #{from_date}..#{to_date}: #{message}")

        SyncRun.update(run, %{
          status: "failed",
          error_message: message,
          duration_ms: elapsed(started_at)
        })

        {:error, message}
    end
  end

  defp import_range(from_date, to_date, on_progress) do
    on_progress.({:phase, :fetching})
    invoices = fetch_range(from_date, to_date)

    on_progress.({:phase, :writing})
    write_invoices(invoices)
  end

  defp fetch_range(from_date, to_date) do
    {from, to} = date_bounds(from_date, to_date)

    %{created: %{gte: from, lte: to}, limit: @page_size}
    |> list_invoices()
    |> Enum.reject(&(Map.get(&1, :status) == "draft"))
    # Paginating Stripe while it is being written to can hand back the same id twice,
    # and Postgres refuses an upsert that touches the same row twice in one statement.
    |> Enum.uniq_by(& &1.id)
    |> Enum.map(&{&1, invoice_lines(&1)})
  end

  # The open and uncollectible invoices issued before the window, fetched again one by
  # one: the list by creation date never returns them once they are out of the window.
  # Best effort - the window is already imported, so a Stripe error here is logged and
  # left to the next day's run rather than failing the run and hiding the window.
  defp refresh_unsettled(before_date) do
    since = DateTime.add(DateTime.utc_now(), -@refresh_days, :day)
    until = DateTime.new!(before_date, ~T[00:00:00], "Etc/UTC")

    from(i in Invoice,
      where: i.status in @unsettled_statuses,
      where: i.invoiced_at >= ^since and i.invoiced_at < ^until,
      select: i.stripe_invoice_id
    )
    |> Repo.all()
    |> Enum.map(&retrieve_invoice/1)
    |> Enum.reject(&(Map.get(&1, :status) == "draft"))
    |> Enum.map(&{&1, invoice_lines(&1)})
    |> write_invoices()
  rescue
    e ->
      message = Exception.message(e)
      Logger.error("InvoiceMirror.Sync could not refresh unsettled invoices: #{message}")

      %{error: message}
  end

  # Every write of a run, the lines' plan backfill included, happens inside the lock.
  # A session-level advisory lock belongs to the connection that took it, so the whole
  # import runs on one checked-out connection - held while Stripe is read too, which
  # is the cost of one import at a time. If the process dies, the connection is closed
  # and Postgres releases the lock.
  defp with_lock(fun) do
    Repo.checkout(
      fn ->
        if acquire_lock() do
          try do
            fun.()
          after
            Repo.query!("SELECT pg_advisory_unlock($1, $2)", [@lock_namespace, @lock_key])
          end
        else
          Logger.info("InvoiceMirror.Sync skipped: another import is already running")
          {:error, :already_running}
        end
      end,
      timeout: :infinity
    )
  end

  defp acquire_lock do
    %{rows: [[acquired?]]} =
      Repo.query!("SELECT pg_try_advisory_lock($1, $2)", [@lock_namespace, @lock_key])

    acquired?
  end

  @doc false
  # Exposed for the test that holds the lock from another connection.
  def lock_keys, do: {@lock_namespace, @lock_key}

  defp elapsed(started_at), do: System.monotonic_time(:millisecond) - started_at

  defp date_bounds(%Date{} = from_date, %Date{} = to_date) do
    from = from_date |> Timex.to_datetime() |> Timex.beginning_of_day() |> DateTime.to_unix()
    to = to_date |> Timex.to_datetime() |> Timex.end_of_day() |> DateTime.to_unix()

    {from, to}
  end

  # ─── Stripe ──────────────────────────────────────────────────────────────

  defp list_invoices(params, acc \\ []) do
    case Sanbase.StripeApi.list_invoices(params) do
      {:ok, %{data: []}} ->
        acc

      {:ok, %{data: data} = response} ->
        acc = acc ++ data

        if Map.get(response, :has_more, false) do
          list_invoices(Map.put(params, :starting_after, List.last(data).id), acc)
        else
          acc
        end

      {:error, error} ->
        raise "Stripe failed to list invoices: #{inspect(error)}"
    end
  end

  defp retrieve_invoice(stripe_invoice_id) do
    case Sanbase.StripeApi.retrieve_invoice(stripe_invoice_id) do
      {:ok, invoice} -> invoice
      {:error, error} -> raise "Stripe failed to retrieve #{stripe_invoice_id}: #{inspect(error)}"
    end
  end

  # The invoice list embeds only the first page of each invoice's lines. An invoice
  # with more lines than that is rare, so the rest is fetched only when Stripe says
  # there is more.
  defp invoice_lines(invoice) do
    lines = Map.get(invoice, :lines) || %{}
    data = Map.get(lines, :data) || []

    lines =
      if Map.get(lines, :has_more, false) and data != [] do
        list_lines(invoice.id, %{limit: @page_size, starting_after: List.last(data).id}, data)
      else
        data
      end

    Enum.uniq_by(lines, & &1.id)
  end

  defp list_lines(invoice_id, params, acc) do
    case Sanbase.StripeApi.list_invoice_line_items(invoice_id, params) do
      {:ok, %{data: []}} ->
        acc

      {:ok, %{data: data} = response} ->
        acc = acc ++ data

        if Map.get(response, :has_more, false) do
          list_lines(invoice_id, Map.put(params, :starting_after, List.last(data).id), acc)
        else
          acc
        end

      {:error, error} ->
        raise "Stripe failed to list the lines of #{invoice_id}: #{inspect(error)}"
    end
  end

  # ─── Writes ──────────────────────────────────────────────────────────────

  defp write_invoices(invoices) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    users = user_ids(Enum.map(invoices, &elem(&1, 0)))
    plans = plan_ids(Enum.flat_map(invoices, &elem(&1, 1)))

    invoices
    |> Enum.chunk_every(@chunk_size)
    |> Enum.reduce(%{invoices_upserted: 0, lines_upserted: 0}, fn chunk, acc ->
      {invoice_count, line_count} = write_chunk(chunk, users, plans, now)

      %{
        invoices_upserted: acc.invoices_upserted + invoice_count,
        lines_upserted: acc.lines_upserted + line_count
      }
    end)
  end

  # A line written before its plan existed locally, or before the plan got its Stripe
  # id, has no plan. Resolved again on every run, so it counts without a re-import.
  defp backfill_plan_ids do
    from(l in InvoiceLine,
      join: p in Plan,
      on: p.stripe_id == l.stripe_price_id,
      where: is_nil(l.plan_id),
      update: [set: [plan_id: p.id]]
    )
    |> Repo.update_all([])
  end

  # One transaction per chunk, so an invoice is never left with half its lines: the
  # invoices are upserted, then their lines are replaced whole. A line removed from an
  # invoice before it was finalized must not survive in the mirror.
  defp write_chunk(chunk, users, plans, now) do
    invoice_entries =
      Enum.map(chunk, fn {invoice, _lines} -> invoice_attrs(invoice, users, now) end)

    {:ok, counts} =
      Repo.transaction(fn ->
        {invoice_count, upserted} =
          Repo.insert_all(Invoice, invoice_entries,
            on_conflict: {:replace, invoice_replace_fields()},
            conflict_target: :stripe_invoice_id,
            returning: [:id, :stripe_invoice_id]
          )

        ids = Map.new(upserted, &{&1.stripe_invoice_id, &1.id})

        from(l in InvoiceLine, where: l.invoice_id in ^Map.values(ids))
        |> Repo.delete_all()

        line_count =
          chunk
          |> Enum.flat_map(fn {invoice, lines} ->
            Enum.map(lines, &line_attrs(&1, Map.fetch!(ids, invoice.id), plans, now))
          end)
          |> insert_lines()

        {invoice_count, line_count}
      end)

    counts
  end

  # Lines are inserted in chunks of their own: an invoice chunk can carry many lines
  # each, and a single statement with all of them risks the parameter limit.
  defp insert_lines(entries) do
    entries
    |> Enum.chunk_every(@chunk_size)
    |> Enum.reduce(0, fn chunk, acc ->
      {count, _} = Repo.insert_all(InvoiceLine, chunk)
      acc + count
    end)
  end

  defp invoice_replace_fields do
    [
      :invoice_number,
      :stripe_customer_id,
      :user_id,
      :customer_email,
      :stripe_subscription_id,
      :status,
      :billing_reason,
      :currency,
      :invoiced_at,
      :paid_at,
      :total,
      :total_excluding_tax,
      :tax,
      :amount_paid,
      :credit_applied,
      :paid_out_of_band,
      :synced_at,
      :updated_at
    ]
  end

  defp invoice_attrs(invoice, users, now) do
    total = Map.get(invoice, :total) || 0
    tax = Map.get(invoice, :tax) || 0

    %{
      stripe_invoice_id: invoice.id,
      invoice_number: Map.get(invoice, :number),
      stripe_customer_id: Map.get(invoice, :customer),
      user_id: user_id(invoice, users),
      customer_email: Map.get(invoice, :customer_email),
      stripe_subscription_id: stripe_id(Map.get(invoice, :subscription)),
      status: Map.get(invoice, :status),
      billing_reason: Map.get(invoice, :billing_reason),
      currency: Map.get(invoice, :currency),
      invoiced_at: to_datetime(Map.get(invoice, :created)) || now,
      paid_at: invoice |> Map.get(:status_transitions) |> paid_at(),
      total: total,
      total_excluding_tax: Map.get(invoice, :total_excluding_tax) || total - tax,
      tax: tax,
      amount_paid: Map.get(invoice, :amount_paid) || 0,
      credit_applied: CreditPayments.credit_applied(invoice),
      paid_out_of_band: Map.get(invoice, :paid_out_of_band) == true,
      synced_at: now,
      inserted_at: now,
      updated_at: now
    }
  end

  defp line_attrs(line, invoice_id, plans, now) do
    amount = Map.get(line, :amount) || 0
    price_id = price_id(line)
    period = Map.get(line, :period) || %{}

    %{
      invoice_id: invoice_id,
      stripe_line_id: line.id,
      stripe_price_id: price_id,
      plan_id: Map.get(plans, price_id),
      description: Map.get(line, :description),
      period_start: to_datetime(Map.get(period, :start)),
      period_end: to_datetime(Map.get(period, :end)),
      amount: amount,
      amount_excluding_tax: Map.get(line, :amount_excluding_tax) || amount,
      quantity: Map.get(line, :quantity),
      proration: Map.get(line, :proration) == true,
      inserted_at: now,
      updated_at: now
    }
  end

  # A line of a legacy plan may carry the plan and no price; the plan id is the same
  # id the price would have had.
  defp price_id(line) do
    stripe_id(Map.get(line, :price)) || stripe_id(Map.get(line, :plan))
  end

  defp paid_at(%{} = transitions), do: to_datetime(Map.get(transitions, :paid_at))
  defp paid_at(_), do: nil

  # Stripe hands back a related object as its id or, when expanded, as the object.
  defp stripe_id(id) when is_binary(id), do: id
  defp stripe_id(%{id: id}) when is_binary(id), do: id
  defp stripe_id(_), do: nil

  defp to_datetime(unix) when is_integer(unix), do: DateTime.from_unix!(unix)
  defp to_datetime(%DateTime{} = dt), do: DateTime.truncate(dt, :second)
  defp to_datetime(_), do: nil

  # ─── Lookups ─────────────────────────────────────────────────────────────

  defp user_id(invoice, users) do
    email = Map.get(invoice, :customer_email)

    Map.get(users.by_customer, Map.get(invoice, :customer)) ||
      (is_binary(email) && Map.get(users.by_email, String.downcase(email))) || nil
  end

  # Matched the way `Sanbase.Billing.CreditPayments` matches: by `stripe_customer_id`
  # first, and failing that by the email Stripe billed. An invoice raised by hand in
  # Stripe never sets `stripe_customer_id` on the user row.
  defp user_ids(invoices) do
    customer_ids = invoices |> Enum.map(&Map.get(&1, :customer)) |> Enum.reject(&is_nil/1)

    emails =
      invoices
      |> Enum.map(&Map.get(&1, :customer_email))
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.downcase/1)

    %{
      by_customer: users_by_customer(Enum.uniq(customer_ids)),
      by_email: users_by_email(Enum.uniq(emails))
    }
  end

  defp users_by_customer([]), do: %{}

  defp users_by_customer(customer_ids) do
    from(u in User,
      where: u.stripe_customer_id in ^customer_ids,
      select: {u.stripe_customer_id, u.id}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp users_by_email([]), do: %{}

  defp users_by_email(emails) do
    from(u in User,
      where: fragment("lower(?)", u.email) in ^emails,
      select: {fragment("lower(?)", u.email), u.id}
    )
    |> Repo.all()
    |> Map.new()
  end

  # A price of a bundle or a one-off invoice item has no plan of ours and maps to nil.
  defp plan_ids(lines) do
    price_ids = lines |> Enum.map(&price_id/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    from(p in Plan, where: p.stripe_id in ^price_ids, select: {p.stripe_id, p.id})
    |> Repo.all()
    |> Map.new()
  end
end
