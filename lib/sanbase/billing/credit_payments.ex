defmodule Sanbase.Billing.CreditPayments do
  @moduledoc ~s"""
  Invoices settled from the customer's Stripe credit balance instead of by a card
  charge - the way crypto payments and wire transfers reach us.

  The manual flow is: add credit to the customer's Stripe balance with the payment
  reference (an etherscan link, a wire reference) in the adjustment's internal note,
  then let the invoice be paid from that balance. Such an invoice produces no charge,
  which is why `Sanbase.Billing.StripeSync` - it exports charges - never sees this
  revenue.

  Stripe has no global endpoint for customer balance transactions; they can only be
  listed one customer at a time. The money is therefore found in two passes:

  1. list the period's invoices (a global, paginated call) and keep the ones whose
     customer balance moved in our favour or that were marked paid out of band;
  2. read the balance ledger of every customer touched by those invoices, which is
     where the internal note - the only record of *how* the money arrived - lives.

  A grant made to a customer with no invoice at all in the period is not reachable
  this way. `customer_ledger/1` reads one customer's full history for those cases.
  """

  import Ecto.Query

  require Logger

  alias Sanbase.Accounts.User
  alias Sanbase.Billing.Subscription.SanBurnCreditTransaction
  alias Sanbase.Repo

  @invoice_page_size 100
  @ledger_page_size 100
  @ledger_concurrency 5
  @ledger_timeout 30_000

  # A transaction with a negative amount credits the customer. Only `adjustment` means
  # money actually reached us - it is the type Stripe gives a manually added credit,
  # both from the dashboard and from `Sanbase.StripeApi.add_credit/3`.
  @payment_type "adjustment"

  # Credit Stripe creates by itself: a downgrade proration or an invoice below the
  # minimum chargeable amount lands on the customer balance instead of being charged,
  # and later pays an invoice. It looks exactly like a payment on the invoice and is
  # not one - the money was collected earlier, by card.
  @stripe_credit_types ~w(invoice_too_small unapplied_from_invoice credit_note invoice_overpaid)

  @stripe_dashboard "https://dashboard.stripe.com"

  # A block explorer link or a hash is the usual note, but a bare "paid in USDT" with no
  # link has to classify too - the ticker is the only signal those carry.
  @crypto_regex ~r/(etherscan\.io\/tx\/|blockchair|blockchain\.com|0x[0-9a-f]{40,}|\b(crypto|eth|btc|usdt|usdc|bnb|sol|matic|dai)\b)/i
  @wire_regex ~r/\b(wire|bank|sepa|swift|iban|transfer|remittance)\b/i
  @trx_hash_regex ~r/0x[0-9a-f]{40,}/i
  # "Burned 19289 SAN for 2700 credits" - a burn credit added by hand never reaches the
  # `san_burn_credit_transactions` table, so the wording has to be enough on its own.
  @san_burn_regex ~r/\bburn(ed|t|ing)?\b/i

  @type invoice_row :: %{
          id: String.t(),
          number: String.t() | nil,
          customer: String.t() | nil,
          user_id: non_neg_integer() | nil,
          email: String.t() | nil,
          created: DateTime.t() | nil,
          stripe_email: String.t() | nil,
          status: String.t() | nil,
          total: integer(),
          amount_paid: integer(),
          credit_applied: integer(),
          paid_out_of_band: boolean(),
          hosted_invoice_url: String.t() | nil,
          invoice_pdf: String.t() | nil,
          source_note: String.t() | nil,
          source: :san_burn | :crypto | :wire | :stripe_credit | :other | :unknown,
          funding_transaction_id: String.t() | nil
        }

  @type grant_row :: %{
          id: String.t(),
          customer: String.t() | nil,
          user_id: non_neg_integer() | nil,
          email: String.t() | nil,
          created: DateTime.t() | nil,
          amount: integer(),
          raw_amount: integer(),
          description: String.t() | nil,
          type: String.t() | nil,
          source: :san_burn | :crypto | :wire | :stripe_credit | :other,
          invoice: String.t() | nil
        }

  @doc ~s"""
  Everything settled outside the card rails between the two dates, inclusive.

  Returns `%{invoices: [...], grants: [...], totals: %{...}, scanned_customers: n}`.
  Amounts are in cents, as Stripe reports them. `credit_applied` is positive when
  credit paid for the invoice; an invoice that only carried debt forward is dropped.

  Every invoice row carries the internal note of the credit that funded it - the note
  lives on the customer's balance ledger, not on the invoice, so it is matched back
  onto the invoice by `attach_note/3`.
  """
  @spec range_report(Date.t(), Date.t()) :: map()
  def range_report(%Date{} = from_date, %Date{} = to_date) do
    {from, to} = date_bounds(from_date, to_date)

    do_report(from, to)
  end

  defp date_bounds(%Date{} = from_date, %Date{} = to_date) do
    from = from_date |> Timex.to_datetime() |> Timex.beginning_of_day() |> DateTime.to_unix()
    to = to_date |> Timex.to_datetime() |> Timex.end_of_day() |> DateTime.to_unix()

    {from, to}
  end

  @doc ~s"""
  `range_report/2` over a single calendar month.
  """
  @spec period_report(pos_integer(), pos_integer()) :: map()
  def period_report(year, month) do
    {from, to} = month_bounds(year, month)

    do_report(from, to)
  end

  @doc ~s"""
  The same data as `range_report/2` before it is summarised, for the importer.

  `transactions` is every ledger entry of every scanned customer, not only the credits
  added inside the range, so the local mirror can re-derive which credit funded which
  invoice without going back to Stripe.
  """
  @spec range_data(Date.t(), Date.t()) :: map()
  def range_data(%Date{} = from_date, %Date{} = to_date) do
    {from, to} = date_bounds(from_date, to_date)
    gathered = gather(from, to)

    %{
      invoices: gathered.invoice_rows,
      transactions:
        Enum.map(
          gathered.raw_transactions,
          &grant_row(&1, gathered.customer_map, gathered.burn_hashes)
        ),
      customer_ids: gathered.customer_ids
    }
  end

  defp do_report(from, to) do
    gathered = gather(from, to)

    invoice_rows = gathered.invoice_rows

    grant_rows =
      gathered.raw_transactions
      |> Enum.filter(&grant_in_period?(&1, from, to))
      |> Enum.map(&grant_row(&1, gathered.customer_map, gathered.burn_hashes))
      |> Enum.sort_by(&sort_key/1, :desc)

    %{
      invoices: invoice_rows,
      grants: grant_rows,
      totals: totals(invoice_rows, grant_rows),
      scanned_customers: length(gathered.customer_ids)
    }
  end

  defp gather(from, to) do
    invoices = list_invoices(%{created: %{gte: from, lte: to}, limit: @invoice_page_size})
    customer_ids = scan_customer_ids(invoices)
    customer_map = customer_user_map(customer_ids, invoices)
    burn_hashes = san_burn_hashes()

    # The whole ledger of every scanned customer, not only the part inside the range:
    # the credit that pays a February invoice is often added in January.
    ledgers = customer_ids |> fetch_ledgers() |> Enum.group_by(&Map.get(&1, :customer))

    %{
      invoice_rows: invoice_rows(invoices, customer_map, ledgers, burn_hashes),
      raw_transactions: Enum.flat_map(ledgers, fn {_customer, transactions} -> transactions end),
      customer_map: customer_map,
      burn_hashes: burn_hashes,
      customer_ids: customer_ids
    }
  end

  defp invoice_rows(invoices, customer_map, ledgers, burn_hashes) do
    invoices
    |> Enum.filter(&settled_outside_stripe?/1)
    |> Enum.map(fn invoice ->
      invoice
      |> invoice_row(customer_map)
      |> attach_note(invoice, Map.get(ledgers, invoice.customer, []), burn_hashes)
    end)
    |> Enum.sort_by(&sort_key/1, :desc)
  end

  @doc ~s"""
  The invoice rows narrowed by source and by a free text query.

  The query matches the customer email, the stripe customer id, the invoice number or
  id, and the source note, case insensitively.
  """
  @spec filter_invoices([invoice_row()], keyword()) :: [invoice_row()]
  def filter_invoices(rows, opts \\ []) do
    source = Keyword.get(opts, :source, :all)
    query = opts |> Keyword.get(:query, "") |> to_string() |> String.trim() |> String.downcase()

    Enum.filter(rows, fn row ->
      (source == :all or row.source == source) and matches_query?(row, query)
    end)
  end

  defp matches_query?(_row, ""), do: true

  defp matches_query?(row, query) do
    [row.email, row.customer, row.number, row.id, row.source_note]
    |> Enum.any?(fn field ->
      is_binary(field) and String.contains?(String.downcase(field), query)
    end)
  end

  @doc ~s"""
  A source filter from a query string parameter, defaulting to `:all`.
  """
  @spec parse_source(String.t() | nil) :: :all | :san_burn | :crypto | :wire | :other | :unknown
  def parse_source(source) when source in ~w(san_burn crypto wire stripe_credit other unknown),
    do: String.to_existing_atom(source)

  def parse_source(_source), do: :all

  @doc ~s"""
  A granularity from a query string parameter, defaulting to `:month`.
  """
  @spec parse_granularity(String.t() | nil) :: :day | :month | :year | :all
  def parse_granularity(granularity) when granularity in ~w(day month year all),
    do: String.to_existing_atom(granularity)

  def parse_granularity(_granularity), do: :month

  @doc ~s"""
  The invoice rows grouped into buckets and summed.

  `granularity` is `:day`, `:month`, `:year` or `:all` - the last one being a single
  bucket for the whole range. Newest bucket first.
  """
  @spec aggregate([invoice_row()], :day | :month | :year | :all) :: [map()]
  def aggregate(invoice_rows, granularity) do
    invoice_rows
    |> Enum.group_by(&bucket(&1, granularity))
    |> Enum.map(fn {label, rows} -> bucket_totals(label, rows) end)
    |> Enum.sort_by(& &1.label, :desc)
  end

  defp bucket_totals(label, rows) do
    %{
      label: label,
      invoice_count: length(rows),
      credit_applied: Enum.reduce(rows, 0, &(&1.credit_applied + &2)),
      card_paid: Enum.reduce(rows, 0, &(&1.amount_paid + &2)),
      total: Enum.reduce(rows, 0, &(&1.total + &2)),
      out_of_band: sum_out_of_band(rows),
      by_source: sum_by_source(rows, & &1.credit_applied)
    }
  end

  defp bucket(%{created: %DateTime{} = dt}, :day), do: Calendar.strftime(dt, "%Y-%m-%d")
  defp bucket(%{created: %DateTime{} = dt}, :month), do: Calendar.strftime(dt, "%Y-%m")
  defp bucket(%{created: %DateTime{} = dt}, :year), do: Calendar.strftime(dt, "%Y")
  defp bucket(_row, :all), do: "Whole range"
  defp bucket(_row, _granularity), do: "Unknown date"

  @doc ~s"""
  The Stripe dashboard page for an invoice.
  """
  @spec stripe_invoice_url(String.t()) :: String.t()
  def stripe_invoice_url(invoice_id), do: "#{@stripe_dashboard}/invoices/#{invoice_id}"

  @doc ~s"""
  The Stripe dashboard page of a customer.

  A balance transaction has no page of its own - its internal note is shown in the
  "Customer invoice balance" section of the customer, which is where this points.
  """
  @spec stripe_customer_url(String.t()) :: String.t()
  def stripe_customer_url(customer_id), do: "#{@stripe_dashboard}/customers/#{customer_id}"

  @doc ~s"""
  The full Stripe balance ledger of a single customer, newest first.

  Unlike `period_report/2` this includes every transaction type, so a credit that has
  not been applied to any invoice yet is visible too.
  """
  @spec customer_ledger(String.t()) :: [grant_row()]
  def customer_ledger(stripe_customer_id) when is_binary(stripe_customer_id) do
    customer_map = customer_user_map([stripe_customer_id])
    burn_hashes = san_burn_hashes()

    stripe_customer_id
    |> list_balance_transactions()
    |> Enum.map(&grant_row(&1, customer_map, burn_hashes))
    |> Enum.sort_by(&sort_key/1, :desc)
  end

  @doc ~s"""
  The stripe customer id behind whatever identifier is at hand.

  Accepts a stripe customer id (returned as is), a Sanbase user id, or an email - the
  three things someone chasing a payment is likely to have. Returns `nil` when nothing
  matches or the matched user has never been a stripe customer.
  """
  @spec resolve_customer_id(String.t() | non_neg_integer()) :: String.t() | nil
  def resolve_customer_id(identifier) when is_integer(identifier),
    do: customer_id_by_user_id(identifier)

  def resolve_customer_id(identifier) when is_binary(identifier) do
    identifier = String.trim(identifier)

    cond do
      identifier == "" -> nil
      String.starts_with?(identifier, "cus_") -> identifier
      String.contains?(identifier, "@") -> customer_id_by_email(identifier)
      true -> resolve_numeric(identifier)
    end
  end

  def resolve_customer_id(_identifier), do: nil

  defp resolve_numeric(identifier) do
    case Integer.parse(identifier) do
      {user_id, ""} -> customer_id_by_user_id(user_id)
      _ -> nil
    end
  end

  @doc ~s"""
  The stripe customer id of the user with that email, or `nil`.
  """
  @spec customer_id_by_email(String.t()) :: String.t() | nil
  def customer_id_by_email(email) when is_binary(email) do
    email = email |> String.trim() |> String.downcase()

    from(u in User,
      where: fragment("lower(?)", u.email) == ^email and not is_nil(u.stripe_customer_id),
      select: u.stripe_customer_id,
      limit: 1
    )
    |> Repo.one()
  end

  @doc ~s"""
  The stripe customer id of that user, or `nil`.
  """
  @spec customer_id_by_user_id(non_neg_integer()) :: String.t() | nil
  def customer_id_by_user_id(user_id) do
    from(u in User,
      where: u.id == ^user_id and not is_nil(u.stripe_customer_id),
      select: u.stripe_customer_id,
      limit: 1
    )
    |> Repo.one()
  end

  @doc ~s"""
  Where the money came from, read off the internal note of a balance adjustment.

  A note naming a transaction hash we recorded ourselves is a SAN burn credit, not a
  payment - those must not be counted as B2B revenue.
  """
  @spec classify_source(String.t() | nil, MapSet.t()) :: :san_burn | :crypto | :wire | :other
  def classify_source(description, burn_hashes) do
    cond do
      is_nil(description) or description == "" ->
        :other

      san_burn_note?(description, burn_hashes) ->
        :san_burn

      Regex.match?(@san_burn_regex, description) and Regex.match?(~r/\bSAN\b/, description) ->
        :san_burn

      Regex.match?(@crypto_regex, description) ->
        :crypto

      Regex.match?(@wire_regex, description) ->
        :wire

      true ->
        :other
    end
  end

  # ─── Invoices ────────────────────────────────────────────────────────────

  # `ending_balance - starting_balance` is what the invoice took out of the customer's
  # balance: positive when credit paid part of it, negative when the invoice merely
  # carried the customer's debt forward. An unfinalized invoice has no ending balance.
  @doc false
  def credit_applied(%{starting_balance: starting, ending_balance: ending})
      when is_integer(starting) and is_integer(ending),
      do: ending - starting

  def credit_applied(_), do: 0

  defp settled_outside_stripe?(invoice) do
    Map.get(invoice, :status) == "paid" and
      (credit_applied(invoice) > 0 or Map.get(invoice, :paid_out_of_band) == true)
  end

  # A customer whose balance moved on any invoice this period may also have been
  # granted credit this period, so their ledger is worth reading even when the
  # invoice itself was paid by card.
  defp scan_customer_ids(invoices) do
    invoices
    |> Enum.filter(fn invoice ->
      Map.get(invoice, :starting_balance, 0) != 0 or
        (Map.get(invoice, :ending_balance) || 0) != 0 or
        Map.get(invoice, :paid_out_of_band) == true
    end)
    |> Enum.map(& &1.customer)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp invoice_row(invoice, customer_map) do
    user = Map.get(customer_map, invoice.customer)

    %{
      id: invoice.id,
      number: Map.get(invoice, :number),
      customer: invoice.customer,
      user_id: user && user.id,
      email: (user && user.email) || Map.get(invoice, :customer_email),
      created: to_datetime(Map.get(invoice, :created)),
      stripe_email: Map.get(invoice, :customer_email),
      status: Map.get(invoice, :status),
      total: Map.get(invoice, :total) || 0,
      amount_paid: Map.get(invoice, :amount_paid) || 0,
      credit_applied: max(credit_applied(invoice), 0),
      paid_out_of_band: Map.get(invoice, :paid_out_of_band) == true,
      hosted_invoice_url: Map.get(invoice, :hosted_invoice_url),
      invoice_pdf: Map.get(invoice, :invoice_pdf),
      source_note: nil,
      source: :unknown,
      funding_transaction_id: nil
    }
  end

  # An invoice records how much credit it consumed but never where that credit came
  # from - the note is on the adjustment that added it. Match the two by time: the
  # last adjustment on or before the moment this invoice drew on the balance, and
  # failing that the first one after it, since credit is sometimes added only once
  # the invoice is already open.
  defp attach_note(row, invoice, transactions, burn_hashes) do
    drawn_at = applied_at(transactions, row.id) || sort_key(row)

    case funding_transaction(transactions, drawn_at) do
      nil ->
        attach_memo(row, invoice, burn_hashes)

      transaction ->
        %{
          row
          | source_note: Map.get(transaction, :description),
            source: transaction_source(transaction, burn_hashes),
            funding_transaction_id: transaction.id
        }
    end
  end

  # An invoice marked paid out of band has no credit adjustment behind it at all - the
  # wire reference, when there is one, was typed into the invoice memo instead.
  defp attach_memo(row, invoice, burn_hashes) do
    case Map.get(invoice, :description) do
      memo when is_binary(memo) and memo != "" ->
        %{row | source_note: memo, source: classify_source(memo, burn_hashes)}

      _ ->
        row
    end
  end

  defp funding_transaction(transactions, drawn_at) do
    adjustments = Enum.filter(transactions, &money_in?/1)

    last_before =
      adjustments
      |> Enum.filter(&(&1.created <= drawn_at))
      |> Enum.max_by(& &1.created, fn -> nil end)

    last_before ||
      adjustments
      |> Enum.filter(&(&1.created > drawn_at))
      |> Enum.min_by(& &1.created, fn -> nil end)
  end

  defp applied_at(transactions, invoice_id) do
    transactions
    |> Enum.find(&(Map.get(&1, :invoice) == invoice_id))
    |> case do
      nil -> nil
      transaction -> Map.get(transaction, :created)
    end
  end

  # Every ledger entry that put credit on the balance, whoever created it.
  defp money_in?(transaction) do
    (Map.get(transaction, :amount) || 0) < 0 and
      Map.get(transaction, :type) in [@payment_type | @stripe_credit_types]
  end

  defp transaction_source(transaction, burn_hashes) do
    case Map.get(transaction, :type) do
      @payment_type -> classify_source(Map.get(transaction, :description), burn_hashes)
      _other -> :stripe_credit
    end
  end

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
        Logger.warning("CreditPayments: failed to list invoices: #{inspect(error)}")
        acc
    end
  end

  # ─── Balance ledgers ─────────────────────────────────────────────────────

  defp fetch_ledgers(customer_ids) do
    customer_ids
    |> Task.async_stream(&list_balance_transactions/1,
      max_concurrency: @ledger_concurrency,
      timeout: @ledger_timeout,
      on_timeout: :kill_task
    )
    |> Enum.flat_map(fn
      {:ok, transactions} -> transactions
      {:exit, _reason} -> []
    end)
  end

  defp list_balance_transactions(customer_id, params \\ %{limit: @ledger_page_size}, acc \\ []) do
    case Sanbase.StripeApi.list_customer_balance_transactions(customer_id, params) do
      {:ok, %{data: []}} ->
        acc

      {:ok, %{data: data} = response} ->
        acc = acc ++ data

        if Map.get(response, :has_more, false) do
          params = Map.put(params, :starting_after, List.last(data).id)
          list_balance_transactions(customer_id, params, acc)
        else
          acc
        end

      {:error, error} ->
        Logger.warning(
          "CreditPayments: failed to list balance transactions for #{customer_id}: #{inspect(error)}"
        )

        acc
    end
  end

  defp grant_in_period?(transaction, from, to) do
    created = Map.get(transaction, :created)

    money_in?(transaction) and is_integer(created) and created >= from and created <= to
  end

  defp grant_row(transaction, customer_map, burn_hashes) do
    customer = Map.get(transaction, :customer)
    user = Map.get(customer_map, customer)
    description = Map.get(transaction, :description)

    %{
      id: transaction.id,
      customer: customer,
      user_id: user && user.id,
      email: user && user.email,
      created: to_datetime(Map.get(transaction, :created)),
      # Stripe signs a credit negative; the dashboard shows money in, so flip it. The
      # raw amount is kept as well - the local mirror stores Stripe's own sign.
      amount: -(Map.get(transaction, :amount) || 0),
      raw_amount: Map.get(transaction, :amount) || 0,
      description: description,
      type: Map.get(transaction, :type),
      source: transaction_source(transaction, burn_hashes),
      invoice: Map.get(transaction, :invoice)
    }
  end

  # ─── Totals ──────────────────────────────────────────────────────────────

  defp totals(invoice_rows, grant_rows) do
    invoice_totals(invoice_rows)
    |> Map.merge(grant_totals(grant_rows))
  end

  defp invoice_totals(invoice_rows) do
    %{
      invoice_count: length(invoice_rows),
      credit_applied: Enum.reduce(invoice_rows, 0, &(&1.credit_applied + &2)),
      payment_credit_applied: sum_credit(invoice_rows, :payments),
      stripe_credit_applied: sum_credit(invoice_rows, :stripe_credit),
      card_paid: Enum.reduce(invoice_rows, 0, &(&1.amount_paid + &2)),
      invoiced_total: Enum.reduce(invoice_rows, 0, &(&1.total + &2)),
      out_of_band_count: Enum.count(invoice_rows, & &1.paid_out_of_band),
      out_of_band_total: sum_out_of_band(invoice_rows),
      credit_applied_by_source: sum_by_source(invoice_rows, & &1.credit_applied),
      unmatched_note_count: Enum.count(invoice_rows, &is_nil(&1.source_note))
    }
  end

  defp grant_totals(grant_rows) do
    %{
      grant_count: Enum.count(grant_rows, &(&1.source != :stripe_credit)),
      credit_granted: sum_grants(grant_rows, :payments),
      stripe_credit_granted: sum_grants(grant_rows, :stripe_credit),
      by_source: sum_by_source(grant_rows, & &1.amount)
    }
  end

  # An invoice settled outside Stripe has nothing in either money column, so its total
  # is the only record of what was actually collected.
  defp sum_out_of_band(rows) do
    rows
    |> Enum.filter(& &1.paid_out_of_band)
    |> Enum.reduce(0, &(&1.total + &2))
  end

  # `credit_applied` counts every dollar of balance an invoice consumed. Only the part
  # funded by an adjustment is money someone sent us; the rest Stripe created itself.
  defp sum_credit(rows, which) do
    rows
    |> filter_by_kind(which)
    |> Enum.reduce(0, &(&1.credit_applied + &2))
  end

  defp sum_grants(rows, which) do
    rows
    |> filter_by_kind(which)
    |> Enum.reduce(0, &(&1.amount + &2))
  end

  defp filter_by_kind(rows, :stripe_credit), do: Enum.filter(rows, &(&1.source == :stripe_credit))
  defp filter_by_kind(rows, :payments), do: Enum.reject(rows, &(&1.source == :stripe_credit))

  defp sum_by_source(rows, amount_fun) do
    Enum.reduce(rows, %{}, fn row, acc ->
      Map.update(acc, row.source, amount_fun.(row), &(&1 + amount_fun.(row)))
    end)
  end

  # ─── Lookups ─────────────────────────────────────────────────────────────

  defp customer_user_map(customer_ids, invoices \\ [])

  defp customer_user_map([], _invoices), do: %{}

  defp customer_user_map(customer_ids, invoices) do
    by_stripe_id =
      from(u in User,
        where: u.stripe_customer_id in ^customer_ids,
        select: %{id: u.id, email: u.email, stripe_customer_id: u.stripe_customer_id}
      )
      |> Repo.all()
      |> Map.new(&{&1.stripe_customer_id, &1})

    # Not every paying customer has `stripe_customer_id` set on their user row - an
    # invoice raised by hand in Stripe never sets it. Stripe still carries the email
    # it was billed to, which is enough to point at the right user record.
    by_email = users_by_invoice_email(customer_ids, invoices, by_stripe_id)

    Map.merge(by_email, by_stripe_id)
  end

  defp users_by_invoice_email(customer_ids, invoices, by_stripe_id) do
    emails_by_customer = emails_by_customer(customer_ids, invoices, by_stripe_id)
    users = users_by_email(Map.values(emails_by_customer))

    emails_by_customer
    |> Enum.map(fn {customer, email} -> {customer, Map.get(users, String.downcase(email))} end)
    |> Enum.reject(fn {_customer, user} -> is_nil(user) end)
    |> Map.new()
  end

  defp emails_by_customer(customer_ids, invoices, by_stripe_id) do
    matched = Map.keys(by_stripe_id)
    wanted = MapSet.new(customer_ids)

    invoices
    |> Enum.filter(fn invoice ->
      customer = Map.get(invoice, :customer)

      customer not in [nil | matched] and MapSet.member?(wanted, customer) and
        is_binary(Map.get(invoice, :customer_email))
    end)
    |> Enum.reduce(%{}, &Map.put_new(&2, &1.customer, &1.customer_email))
  end

  defp users_by_email([]), do: %{}

  defp users_by_email(emails) do
    emails = emails |> Enum.map(&String.downcase/1) |> Enum.uniq()

    from(u in User,
      where: fragment("lower(?)", u.email) in ^emails,
      select: %{id: u.id, email: u.email}
    )
    |> Repo.all()
    |> Map.new(&{String.downcase(&1.email), &1})
  end

  defp san_burn_hashes do
    from(s in SanBurnCreditTransaction, select: s.trx_hash)
    |> Repo.all()
    |> Enum.reject(&is_nil/1)
    |> MapSet.new(&String.downcase/1)
  end

  defp san_burn_note?(description, burn_hashes) do
    case Regex.run(@trx_hash_regex, description) do
      [hash | _] -> MapSet.member?(burn_hashes, String.downcase(hash))
      _ -> false
    end
  end

  # ─── Misc ────────────────────────────────────────────────────────────────

  defp month_bounds(year, month) do
    from = Timex.beginning_of_month(year, month) |> Timex.to_datetime() |> DateTime.to_unix()
    # `end_of_month` gives the last day at midnight, which would drop everything
    # invoiced during that day.
    to =
      Timex.end_of_month(year, month)
      |> Timex.to_datetime()
      |> Timex.end_of_day()
      |> DateTime.to_unix()

    {from, to}
  end

  defp sort_key(%{created: %DateTime{} = dt}), do: DateTime.to_unix(dt)
  defp sort_key(_), do: 0

  defp to_datetime(unix) when is_integer(unix), do: DateTime.from_unix!(unix)
  defp to_datetime(%DateTime{} = dt), do: dt
  defp to_datetime(_), do: nil
end
