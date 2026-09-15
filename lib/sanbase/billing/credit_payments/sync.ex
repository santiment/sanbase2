defmodule Sanbase.Billing.CreditPayments.Sync do
  @moduledoc ~s"""
  Imports credit-settled invoices and customer balance ledgers from Stripe into the
  local mirror.

  Every write is an upsert keyed by the Stripe id, so importing the same range twice
  is harmless and a second run after the classification changes rewrites the derived
  `source`/`source_note` of rows that are already there. That is the intended way to
  repair anything an earlier version of this code got wrong or skipped: widen the
  range and run it again.

  A daily run keeps the recent past fresh; the admin panel triggers wider ranges by
  hand through `Sanbase.Billing.CreditPayments.SyncJob`.
  """

  import Ecto.Query

  require Logger

  alias Sanbase.Billing.CreditPayments

  alias Sanbase.Billing.CreditPayments.{
    CreditBalanceTransaction,
    CreditInvoice,
    SyncRun
  }

  alias Sanbase.Repo

  @default_recent_days 7
  @chunk_size 500

  @doc ~s"""
  Imports the last `days` days, the daily scheduled entry point.

  The window overlaps itself on purpose: an invoice paid days after it was issued, or
  a note typed into Stripe later, is picked up by the next run.
  """
  @spec run(non_neg_integer()) :: {:ok, map()} | {:error, any()}
  def run(days \\ @default_recent_days) do
    today = Date.utc_today()

    sync_range(Date.add(today, -days), today)
  end

  @doc ~s"""
  Imports one date range, recording the run so the coverage stays auditable.

  `opts` accepts `:triggered_by` (a user id) and `:on_progress`, a one argument
  function called with `{:phase, atom}` as the import moves along.
  """
  @spec sync_range(Date.t(), Date.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def sync_range(%Date{} = from_date, %Date{} = to_date, opts \\ []) do
    started_at = System.monotonic_time(:millisecond)
    on_progress = Keyword.get(opts, :on_progress, fn _event -> :ok end)

    {:ok, run} =
      SyncRun.create(%{
        from_date: from_date,
        to_date: to_date,
        status: "running",
        triggered_by: Keyword.get(opts, :triggered_by)
      })

    try do
      summary = import_range(from_date, to_date, on_progress)

      {:ok, run} =
        SyncRun.update(run, %{
          status: "completed",
          invoices_upserted: summary.invoices_upserted,
          grants_upserted: summary.grants_upserted,
          customers_scanned: summary.customers_scanned,
          duration_ms: elapsed(started_at)
        })

      on_progress.({:phase, :done})

      {:ok, Map.put(summary, :run, run)}
    rescue
      e ->
        message = Exception.message(e)
        Logger.error("CreditPayments.Sync failed for #{from_date}..#{to_date}: #{message}")

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
    data = CreditPayments.range_data(from_date, to_date)

    on_progress.({:phase, :writing})
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    invoices_upserted = upsert_invoices(data.invoices, now)
    grants_upserted = upsert_transactions(data.transactions, now)
    prune_stale(from_date, to_date, Enum.map(data.invoices, & &1.id))

    %{
      invoices_upserted: invoices_upserted,
      grants_upserted: grants_upserted,
      customers_scanned: length(data.customer_ids)
    }
  end

  defp elapsed(started_at), do: System.monotonic_time(:millisecond) - started_at

  # ─── Writes ──────────────────────────────────────────────────────────────

  defp upsert_invoices(rows, now) do
    rows
    # Postgres refuses an upsert that touches the same row twice in one statement, and
    # paginating Stripe while it is being written to can hand back the same id twice.
    |> Enum.uniq_by(& &1.id)
    |> Enum.map(&invoice_attrs(&1, now))
    |> upsert_all(CreditInvoice, :stripe_invoice_id, [
      :invoice_number,
      :stripe_customer_id,
      :user_id,
      :customer_email,
      :invoiced_at,
      :status,
      :total,
      :amount_paid,
      :credit_applied,
      :paid_out_of_band,
      :hosted_invoice_url,
      :invoice_pdf,
      :source,
      :source_note,
      :funding_transaction_id,
      :synced_at,
      :updated_at
    ])
  end

  defp upsert_transactions(rows, now) do
    rows
    |> Enum.reject(&is_nil(&1.customer))
    |> Enum.uniq_by(& &1.id)
    |> Enum.map(&transaction_attrs(&1, now))
    |> upsert_all(CreditBalanceTransaction, :stripe_transaction_id, [
      :stripe_customer_id,
      :user_id,
      :granted_at,
      :amount,
      :type,
      :description,
      :stripe_invoice_id,
      :source,
      :synced_at,
      :updated_at
    ])
  end

  # `insert_all` in chunks: a wide backfill can carry thousands of rows, and a single
  # statement with all of them risks the parameter limit.
  defp upsert_all([], _schema, _conflict_target, _replace_fields), do: 0

  defp upsert_all(entries, schema, conflict_target, replace_fields) do
    entries
    |> Enum.chunk_every(@chunk_size)
    |> Enum.reduce(0, fn chunk, acc ->
      {count, _} =
        Repo.insert_all(schema, chunk,
          on_conflict: {:replace, replace_fields},
          conflict_target: conflict_target
        )

      acc + count
    end)
  end

  defp invoice_attrs(row, now) do
    %{
      stripe_invoice_id: row.id,
      invoice_number: row.number,
      stripe_customer_id: row.customer,
      user_id: row.user_id,
      customer_email: row.email,
      invoiced_at: truncate(row.created) || now,
      status: row.status,
      total: row.total,
      amount_paid: row.amount_paid,
      credit_applied: row.credit_applied,
      paid_out_of_band: row.paid_out_of_band,
      hosted_invoice_url: row.hosted_invoice_url,
      invoice_pdf: row.invoice_pdf,
      source: to_string(row.source),
      source_note: row.source_note,
      funding_transaction_id: row.funding_transaction_id,
      synced_at: now,
      inserted_at: now,
      updated_at: now
    }
  end

  defp transaction_attrs(row, now) do
    %{
      stripe_transaction_id: row.id,
      stripe_customer_id: row.customer,
      user_id: row.user_id,
      granted_at: truncate(row.created) || now,
      amount: row.raw_amount,
      type: row.type,
      description: row.description,
      stripe_invoice_id: row.invoice,
      source: to_string(row.source),
      synced_at: now,
      inserted_at: now,
      updated_at: now
    }
  end

  defp truncate(%DateTime{} = dt), do: DateTime.truncate(dt, :second)
  defp truncate(_), do: nil

  # ─── Housekeeping ────────────────────────────────────────────────────────

  @doc ~s"""
  Drops mirrored invoices in the range that Stripe no longer settles from credit.

  An invoice can stop qualifying - a credit is reversed, an invoice is voided - and
  without this it would stay in the mirror for good. Keyed on the ids the import just
  wrote rather than on a timestamp, so two runs in the same second cannot delete each
  other's rows.
  """
  @spec prune_stale(Date.t(), Date.t(), [String.t()]) :: non_neg_integer()
  def prune_stale(%Date{} = from_date, %Date{} = to_date, kept_ids) do
    from_dt = from_date |> Timex.to_datetime() |> Timex.beginning_of_day()
    to_dt = to_date |> Timex.to_datetime() |> Timex.end_of_day()

    {count, _} =
      from(i in CreditInvoice,
        where:
          i.invoiced_at >= ^from_dt and i.invoiced_at <= ^to_dt and
            i.stripe_invoice_id not in ^kept_ids
      )
      |> Repo.delete_all()

    count
  end
end
