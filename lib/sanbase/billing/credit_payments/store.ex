defmodule Sanbase.Billing.CreditPayments.Store do
  @moduledoc ~s"""
  Reads the local mirror of credit payments.

  Returns rows in exactly the shape `Sanbase.Billing.CreditPayments` builds from the
  Stripe API, so the admin panel, the aggregations and the CSV export do not care
  which of the two they were handed. The difference is speed: this reads Postgres,
  the other paginates Stripe.
  """

  import Ecto.Query

  alias Sanbase.Billing.CreditPayments
  alias Sanbase.Accounts.User
  alias Sanbase.Billing.CreditPayments.{CreditBalanceTransaction, CreditInvoice, SyncRun}
  alias Sanbase.Repo

  @grant_type "adjustment"

  @doc ~s"""
  The mirrored report for a date range, shaped like `CreditPayments.range_report/2`.

  `coverage` says which parts of the range no completed import covers - an empty list
  means every day in it has been imported at least once.
  """
  @spec range_report(Date.t(), Date.t()) :: map()
  def range_report(%Date{} = from_date, %Date{} = to_date) do
    invoice_rows = invoices(from_date, to_date)
    grant_rows = grants(from_date, to_date)

    %{
      invoices: invoice_rows,
      grants: grant_rows,
      totals: totals(invoice_rows, grant_rows),
      scanned_customers: count_customers(invoice_rows, grant_rows),
      coverage: SyncRun.gaps(from_date, to_date),
      last_synced_at: last_synced_at()
    }
  end

  @doc ~s"""
  The mirrored credit-settled invoices in the range, newest first.
  """
  @spec invoices(Date.t(), Date.t()) :: [map()]
  def invoices(%Date{} = from_date, %Date{} = to_date) do
    {from, to} = bounds(from_date, to_date)

    from(i in CreditInvoice,
      left_join: u in assoc(i, :user),
      # Rows imported before the customer was matched to a user keep only the stripe
      # customer id - this second join links them without a re-import.
      left_join: c in User,
      on: is_nil(i.user_id) and c.stripe_customer_id == i.stripe_customer_id,
      where: i.invoiced_at >= ^from and i.invoiced_at <= ^to,
      order_by: [desc: i.invoiced_at, desc: i.id],
      select: {i, coalesce(u.email, c.email), coalesce(i.user_id, c.id)}
    )
    |> Repo.all()
    |> Enum.map(&invoice_row/1)
  end

  @doc ~s"""
  The mirrored credit added in the range, newest first.
  """
  @spec grants(Date.t(), Date.t()) :: [map()]
  def grants(%Date{} = from_date, %Date{} = to_date) do
    {from, to} = bounds(from_date, to_date)

    from(t in CreditBalanceTransaction,
      left_join: u in assoc(t, :user),
      left_join: c in User,
      on: is_nil(t.user_id) and c.stripe_customer_id == t.stripe_customer_id,
      where:
        t.granted_at >= ^from and t.granted_at <= ^to and t.type == ^@grant_type and t.amount < 0,
      order_by: [desc: t.granted_at, desc: t.id],
      select: {t, coalesce(u.email, c.email), coalesce(t.user_id, c.id)}
    )
    |> Repo.all()
    |> Enum.map(&grant_row/1)
  end

  @doc ~s"""
  The mirrored balance ledger of one customer, newest first - every entry, not only
  the credits added.
  """
  @spec customer_ledger(String.t()) :: [map()]
  def customer_ledger(stripe_customer_id) when is_binary(stripe_customer_id) do
    from(t in CreditBalanceTransaction,
      left_join: u in assoc(t, :user),
      left_join: c in User,
      on: is_nil(t.user_id) and c.stripe_customer_id == t.stripe_customer_id,
      where: t.stripe_customer_id == ^stripe_customer_id,
      order_by: [desc: t.granted_at, desc: t.id],
      select: {t, coalesce(u.email, c.email), coalesce(t.user_id, c.id)}
    )
    |> Repo.all()
    |> Enum.map(&grant_row/1)
  end

  @doc ~s"""
  When the mirror was last written to, or `nil` when nothing has been imported.
  """
  @spec last_synced_at() :: DateTime.t() | nil
  def last_synced_at do
    case SyncRun.last_completed() do
      nil -> nil
      run -> run.updated_at
    end
  end

  # ─── Row shaping ─────────────────────────────────────────────────────────

  defp invoice_row({invoice, user_email, user_id}) do
    %{
      id: invoice.stripe_invoice_id,
      number: invoice.invoice_number,
      customer: invoice.stripe_customer_id,
      user_id: user_id,
      email: user_email || invoice.customer_email,
      created: invoice.invoiced_at,
      status: invoice.status,
      total: invoice.total,
      amount_paid: invoice.amount_paid,
      credit_applied: invoice.credit_applied,
      paid_out_of_band: invoice.paid_out_of_band,
      hosted_invoice_url: invoice.hosted_invoice_url,
      invoice_pdf: invoice.invoice_pdf,
      source_note: invoice.source_note,
      source: to_source(invoice.source),
      funding_transaction_id: invoice.funding_transaction_id
    }
  end

  defp grant_row({transaction, user_email, user_id}) do
    %{
      id: transaction.stripe_transaction_id,
      customer: transaction.stripe_customer_id,
      user_id: user_id,
      email: user_email,
      created: transaction.granted_at,
      # The mirror keeps Stripe's sign; money in is the flipped one.
      amount: -transaction.amount,
      raw_amount: transaction.amount,
      description: transaction.description,
      type: transaction.type,
      source: to_source(transaction.source),
      invoice: transaction.stripe_invoice_id
    }
  end

  defp to_source(nil), do: :unknown

  defp to_source(source) when is_binary(source) do
    CreditPayments.parse_source(source)
    |> case do
      :all -> :unknown
      parsed -> parsed
    end
  end

  # ─── Totals ──────────────────────────────────────────────────────────────

  defp totals(invoice_rows, grant_rows) do
    %{
      invoice_count: length(invoice_rows),
      credit_applied: sum(invoice_rows, & &1.credit_applied),
      card_paid: sum(invoice_rows, & &1.amount_paid),
      invoiced_total: sum(invoice_rows, & &1.total),
      out_of_band_count: Enum.count(invoice_rows, & &1.paid_out_of_band),
      out_of_band_total: out_of_band_total(invoice_rows),
      credit_applied_by_source: by_source(invoice_rows, & &1.credit_applied),
      unmatched_note_count: Enum.count(invoice_rows, &is_nil(&1.source_note)),
      grant_count: length(grant_rows),
      credit_granted: sum(grant_rows, & &1.amount),
      by_source: by_source(grant_rows, & &1.amount)
    }
  end

  defp sum(rows, fun), do: Enum.reduce(rows, 0, &(fun.(&1) + &2))

  # Nothing lands in either money column for an invoice settled outside Stripe, so its
  # total is the only record of what was collected.
  defp out_of_band_total(rows) do
    rows |> Enum.filter(& &1.paid_out_of_band) |> sum(& &1.total)
  end

  defp by_source(rows, fun) do
    Enum.reduce(rows, %{}, fn row, acc ->
      Map.update(acc, row.source, fun.(row), &(&1 + fun.(row)))
    end)
  end

  defp count_customers(invoice_rows, grant_rows) do
    (Enum.map(invoice_rows, & &1.customer) ++ Enum.map(grant_rows, & &1.customer))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> length()
  end

  defp bounds(%Date{} = from_date, %Date{} = to_date) do
    from = from_date |> Timex.to_datetime() |> Timex.beginning_of_day()
    to = to_date |> Timex.to_datetime() |> Timex.end_of_day()

    {from, to}
  end
end
