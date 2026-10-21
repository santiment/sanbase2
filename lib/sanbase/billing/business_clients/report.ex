defmodule Sanbase.Billing.BusinessClients.Report do
  @moduledoc ~s"""
  The numbers of the Business Clients page: the client list, churn and renewal, one
  client's history, and the export of business-email users.

  Everything is derived from the paid lines of the invoice mirror
  (`Sanbase.Billing.InvoiceMirror`). The data is loaded once per call - the lines of
  the business plans only, filtered by plan id in SQL - and the arithmetic is done by
  the pure functions in `Sanbase.Billing.BusinessClients.Periods`.

  Which lines count for a user:

    * every line of a plan matching `business_plan_patterns`;
    * a line of a `business_email_plan_names` plan of a `business_email_product_ids`
      product when the user's email is not a free provider, or an admin override says
      yes (an override of no excludes them).

  `@santiment.net` users never count. All amounts are cents, excluding tax.
  """

  import Ecto.Query

  alias Sanbase.Accounts.User
  alias Sanbase.Billing.{Plan, Subscription}
  alias Sanbase.Billing.BusinessClients
  alias Sanbase.Billing.BusinessClients.{LogEntry, MetricsSnapshot, Periods, Settings}
  alias Sanbase.Billing.BusinessClients.{Snapshots, Usage}
  alias Sanbase.Billing.CreditPayments.CreditInvoice
  alias Sanbase.Billing.InvoiceMirror.{Invoice, InvoiceLine}
  alias Sanbase.Repo

  @team_email_pattern "%@santiment.net"

  # An invoice left open this long after it was issued is a failed payment, not one
  # Stripe is still retrying in its first days.
  @failed_payment_after_days 7

  # `stripe_credit_invoices.source` values, mapped without creating atoms.
  @credit_sources %{
    "san_burn" => :san_burn,
    "crypto" => :crypto,
    "wire" => :wire,
    "stripe_credit" => :stripe_credit,
    "other" => :other,
    "unknown" => :unknown
  }

  @paid_by_keys [:card, :wire, :crypto, :san_burn, :stripe_credit, :other, :unknown, :out_of_band]

  @live_statuses [:active, :trialing, :past_due, :unpaid]
  @failed_statuses [:past_due, :unpaid]

  @unknown_user %{email: nil, username: nil, stripe_customer_id: nil}

  # ─── Page ────────────────────────────────────────────────────────────────

  @doc ~s"""
  Everything the Business Clients page shows, from one load of the data:
  `%{clients: list_clients/1, metrics: metrics/1, monthly: monthly_metrics/1}`.

  Options: `:as_of` (default today) for the clients and the metrics, `:months`
  (default 12) for the monthly history, which always ends at the current month.
  """
  @spec page(Keyword.t()) :: %{clients: [map()], metrics: map(), monthly: [map()]}
  def page(opts \\ []) do
    as_of = Keyword.get(opts, :as_of, Date.utc_today())
    months = last_months(Keyword.get(opts, :months, 12))
    data = load(Settings.get())

    %{
      clients: build_clients(data, as_of),
      metrics: metrics_for(data, as_of),
      monthly: monthly_from(months, metrics_snapshots(months), data)
    }
  end

  # ─── Client list ─────────────────────────────────────────────────────────

  @doc ~s"""
  The clients active on `as_of` (default today), highest MRR first.

  See the moduledoc of `Sanbase.Billing.BusinessClients` for the shape of a client.
  Usage comes from ClickHouse and is `nil` when the query fails.
  """
  @spec list_clients(Keyword.t()) :: [map()]
  def list_clients(opts \\ []) do
    as_of = Keyword.get(opts, :as_of, Date.utc_today())

    Settings.get()
    |> load()
    |> build_clients(as_of)
  end

  # ─── Metrics ─────────────────────────────────────────────────────────────

  @doc ~s"""
  Headline numbers on `as_of` (default today): client count, at-risk count, client
  and revenue churn, client and revenue renewal. Rates are fractions, `nil` when there
  is nothing to divide by.
  """
  @spec metrics(Keyword.t()) :: map()
  def metrics(opts \\ []) do
    as_of = Keyword.get(opts, :as_of, Date.utc_today())

    Settings.get()
    |> load()
    |> metrics_for(as_of)
  end

  @doc ~s"""
  `metrics/1` on the first day of each of the last `months` months (default 12),
  newest first. A month with a stored `MetricsSnapshot` returns it
  (`source: :snapshot`); any other month is computed now (`source: :computed`).
  """
  @spec monthly_metrics(Keyword.t()) :: [map()]
  def monthly_metrics(opts \\ []) do
    months = last_months(Keyword.get(opts, :months, 12))
    snapshots = metrics_snapshots(months)

    # Loaded only when some month has no snapshot.
    data = if Enum.all?(months, &Map.has_key?(snapshots, &1)), do: nil, else: load(Settings.get())

    monthly_from(months, snapshots, data)
  end

  # The first day of each of the last `count` months, newest first.
  defp last_months(count) do
    current = Date.beginning_of_month(Date.utc_today())

    for i <- 0..(count - 1)//1, do: Date.shift(current, month: -i)
  end

  defp metrics_snapshots(months) do
    from(s in MetricsSnapshot, where: s.month in ^months, select: {s.month, s.data})
    |> Repo.all()
    |> Map.new()
  end

  defp monthly_from(months, snapshots, data) do
    Enum.map(months, fn month ->
      case Map.fetch(snapshots, month) do
        {:ok, stored} ->
          stored |> Snapshots.metrics_from_data() |> Map.merge(%{month: month, source: :snapshot})

        :error ->
          data |> metrics_for(month) |> Map.merge(%{month: month, source: :computed})
      end
    end)
  end

  # ─── Client detail ───────────────────────────────────────────────────────

  @doc ~s"""
  One user's page: the client map (`nil` when not a current client), every mirrored
  invoice with its lines, newest first, the log entries and the override.
  """
  @spec client_detail(integer()) :: map()
  def client_detail(user_id) do
    settings = Settings.get()
    data = load(settings, [user_id])
    client = data |> build_clients(Date.utc_today()) |> List.first()

    user =
      case Repo.get(User, user_id) do
        nil -> nil
        user -> %{id: user.id, email: user.email, username: user.username}
      end

    %{
      client: client,
      user: user,
      invoices: invoices_of(user_id),
      entries: BusinessClients.list_entries(user_id),
      override: Map.get(data.overrides, user_id)
    }
  end

  # ─── Business email export ───────────────────────────────────────────────

  @doc ~s"""
  Every user whose email domain is not a free provider, for the CSV export, with the
  plan of their live subscription and whether they pay. The domain filter runs in SQL.
  """
  @spec business_email_users() :: [map()]
  def business_email_users do
    free_domains = Settings.get().free_email_domains |> Enum.map(&String.downcase/1)

    # The best live subscription per user: paying before trialing, then the dearest.
    subscriptions =
      from(s in Subscription,
        join: p in assoc(s, :plan),
        where: s.status in [:active, :past_due, :trialing],
        distinct: s.user_id,
        order_by: [
          asc: s.user_id,
          desc: fragment("(? IN ('active', 'past_due') AND ? > 0)", s.status, p.amount),
          desc: p.amount,
          desc: s.id
        ],
        select: %{user_id: s.user_id, plan_name: p.name, status: s.status, amount: p.amount}
      )

    from(u in User,
      left_join: s in subquery(subscriptions),
      on: s.user_id == u.id,
      where: not is_nil(u.email) and not ilike(u.email, @team_email_pattern),
      where: fragment("split_part(lower(trim(?)), '@', 2) <> ''", u.email),
      where: fragment("split_part(lower(trim(?)), '@', 2) <> ALL(?)", u.email, ^free_domains),
      order_by: [asc: u.id],
      select: %{
        user_id: u.id,
        email: u.email,
        username: u.username,
        registered_at: u.inserted_at,
        plan_name: s.plan_name,
        status: s.status,
        amount: s.amount
      }
    )
    |> Repo.all()
    |> Enum.map(fn row ->
      paying? = row.status in [:active, :past_due] and (row.amount || 0) > 0
      row |> Map.drop([:status, :amount]) |> Map.put(:paying?, paying?)
    end)
  end

  # ─── Formula notes ───────────────────────────────────────────────────────

  @doc ~s"""
  A plain-English explanation of every number on the page, with the current
  parameter values filled in.
  """
  @spec formula_notes(map()) :: %{atom() => String.t()}
  def formula_notes(settings) do
    window = "rolling #{settings.churn_window_months} months"
    grace = "#{settings.renewal_grace_days}-day grace"
    intervals = Enum.join(settings.renewal_intervals, "/")
    email_plans = Enum.join(settings.business_email_plan_names, "/")
    usage_days = settings.usage_window_days

    upgrades =
      if settings.renewal_upgrades_full_value,
        do: "Upgrades count at their full new value.",
        else: "Each new ACV is capped at the old one, so upgrades do not lift the rate."

    %{
      business_client:
        "One user account with a paid invoice line of a business plan " <>
          "(#{Enum.join(settings.business_plan_patterns, ", ")}) covering today, or of a " <>
          "Sanbase #{email_plans} plan when the email is not a free provider " <>
          "(#{length(settings.free_email_domains)} domains) or an admin override says so. " <>
          "Team accounts, legacy enterprise and API bundles are excluded.",
      acv:
        "Annual contract value: the monthly value of the lines in force today times 12. " <>
          "A line's monthly value is its amount excluding tax divided by the months it covers. " <>
          "Refunds and credit notes are not deducted.",
      tcv:
        "Total contract value: everything paid to date for business plans, excluding tax, " <>
          "including prorations, whatever the payment method. Refunds and credit notes " <>
          "are not deducted.",
      client_churn:
        "Of the clients active #{settings.churn_window_months} months ago (#{window}), " <>
          "the share not active today. Switching plans is not churn.",
      revenue_churn:
        "Of the MRR those clients paid #{settings.churn_window_months} months ago, the share " <>
          "lost since: each client adds what their MRR dropped, so downgrades count. " <>
          "Upgrades are shown separately as expansion and do not offset losses.",
      client_renewal:
        "Of the #{intervals} periods that ended in the #{window} and are past their #{grace} " <>
          "(or already renewed), the share followed by a paid business period starting " <>
          "within the grace. Periods still inside the grace are pending and left out.",
      revenue_renewal:
        "The new ACV of the renewed #{intervals} periods over the old ACV of all due ones " <>
          "(#{window}, #{grace}). #{upgrades}",
      at_risk:
        "Clients whose most severe open log entry is at risk or high risk. " <>
          "Set by hand in the client log; there are no automatic rules yet.",
      retention:
        "Share of at-risk clients with at least one \"#{settings.retention_action_type}\" " <>
          "entry in their log.",
      usage:
        "API key calls in the last #{usage_days} days against the #{usage_days} days before, " <>
          "and the last web session. Shown for context only; no number depends on them."
    }
  end

  # ─── Loading ─────────────────────────────────────────────────────────────

  # Everything the formulas need, in one pass: the business plans, the eligible lines
  # of every user grouped by user, users, overrides, log entries and the credit sources
  # of their invoices. The log entries are filtered by date in memory, so computing many
  # months from one load queries them once.
  defp load(settings, user_ids \\ nil) do
    plans = classify_plans(settings)
    rows = line_rows(Map.keys(plans), user_ids)
    overrides = BusinessClients.overrides()
    users = users_by_id(rows |> Enum.map(& &1.user_id) |> Enum.uniq())
    lines_by_user = eligible_lines_by_user(rows, plans, users, overrides, settings)

    %{
      settings: settings,
      plans: plans,
      users: users,
      overrides: overrides,
      lines_by_user: lines_by_user,
      entries_by_user: entries_by_user(Map.keys(lines_by_user)),
      credit_sources: credit_sources(rows |> Enum.map(& &1.stripe_invoice_id) |> Enum.uniq())
    }
  end

  # A business plan line always counts; a business-email plan line only for a user
  # whose email or override qualifies. Users left with no line are not clients.
  defp eligible_lines_by_user(rows, plans, users, overrides, settings) do
    rows
    |> Enum.map(&to_line(&1, plans))
    |> Enum.group_by(& &1.user_id)
    |> Enum.map(fn {user_id, lines} ->
      email_ok? = email_eligible?(Map.get(users, user_id), overrides, settings)
      {user_id, Enum.filter(lines, &(&1.kind == :business or email_ok?))}
    end)
    |> Enum.reject(fn {_user_id, lines} -> lines == [] end)
    |> Map.new()
  end

  # plan id => plan info with `kind: :business | :email`.
  defp classify_plans(settings) do
    patterns = Enum.map(settings.business_plan_patterns, &String.upcase/1)
    email_names = Enum.map(settings.business_email_plan_names, &String.upcase/1)
    email_products = settings.business_email_product_ids

    from(p in Plan,
      select: %{id: p.id, name: p.name, product_id: p.product_id, interval: p.interval}
    )
    |> Repo.all()
    |> Enum.flat_map(fn plan ->
      name = String.upcase(plan.name || "")

      cond do
        Enum.any?(patterns, &name_matches?(name, &1)) ->
          [{plan.id, Map.put(plan, :kind, :business)}]

        name in email_names and plan.product_id in email_products ->
          [{plan.id, Map.put(plan, :kind, :email)}]

        true ->
          []
      end
    end)
    |> Map.new()
  end

  defp name_matches?(name, pattern) do
    case String.split_at(pattern, -1) do
      {prefix, "*"} -> String.starts_with?(name, prefix)
      _ -> name == pattern
    end
  end

  # Every line of a paid invoice on one of the plans. The invoice's user is taken from
  # `user_id`, or from the Stripe customer when the sync could not resolve it.
  defp line_rows([], _user_ids), do: []

  defp line_rows(plan_ids, user_ids) do
    query =
      from([line: l, price_plan: p] in lines_with_plan(),
        join: i in Invoice,
        on: i.id == l.invoice_id,
        left_join: u1 in User,
        as: :invoice_user,
        on: u1.id == i.user_id,
        left_join: u2 in User,
        as: :customer_user,
        on: is_nil(i.user_id) and u2.stripe_customer_id == i.stripe_customer_id,
        where: i.status == "paid" and coalesce(l.plan_id, p.id) in ^plan_ids,
        where: not is_nil(coalesce(u1.id, u2.id)),
        where: not ilike(coalesce(coalesce(u1.email, u2.email), ""), @team_email_pattern),
        select: %{
          user_id: coalesce(u1.id, u2.id),
          line_id: l.id,
          plan_id: coalesce(l.plan_id, p.id),
          period_start: l.period_start,
          period_end: l.period_end,
          amount: l.amount_excluding_tax,
          proration: l.proration,
          invoice_id: i.id,
          stripe_invoice_id: i.stripe_invoice_id,
          stripe_subscription_id: i.stripe_subscription_id,
          invoiced_at: i.invoiced_at,
          amount_paid: i.amount_paid,
          credit_applied: i.credit_applied,
          paid_out_of_band: i.paid_out_of_band
        }
      )

    query =
      if user_ids,
        do:
          where(
            query,
            [invoice_user: u1, customer_user: u2],
            coalesce(u1.id, u2.id) in ^user_ids
          ),
        else: query

    Repo.all(query)
  end

  # Lines with their plan, resolved from the Stripe price when the line was written
  # before the plan existed locally or had its Stripe id. The next sync backfills
  # `plan_id`; until then the price says which plan it is.
  defp lines_with_plan do
    from(l in InvoiceLine,
      as: :line,
      left_join: p in Plan,
      as: :price_plan,
      on: is_nil(l.plan_id) and p.stripe_id == l.stripe_price_id
    )
  end

  defp to_line(row, plans) do
    plan = Map.fetch!(plans, row.plan_id)

    Map.merge(row, %{
      period_start: to_date(row.period_start),
      period_end: to_date(row.period_end),
      subscription: row.stripe_subscription_id || {:line, row.line_id},
      plan_name: plan.name,
      product_id: plan.product_id,
      interval: plan.interval,
      kind: plan.kind
    })
  end

  defp users_by_id([]), do: %{}

  defp users_by_id(user_ids) do
    from(u in User,
      where: u.id in ^user_ids,
      select:
        {u.id,
         %{
           id: u.id,
           email: u.email,
           username: u.username,
           stripe_customer_id: u.stripe_customer_id
         }}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp email_eligible?(nil, _overrides, _settings), do: false

  defp email_eligible?(user, overrides, settings) do
    case Map.get(overrides, user.id) do
      nil -> BusinessClients.business_email?(user.email, settings.free_email_domains)
      business? -> business?
    end
  end

  defp entries_by_user([]), do: %{}

  defp entries_by_user(user_ids) do
    from(e in LogEntry, where: e.user_id in ^user_ids)
    |> Repo.all()
    |> Enum.group_by(& &1.user_id)
  end

  defp credit_sources([]), do: %{}

  defp credit_sources(stripe_invoice_ids) do
    from(c in CreditInvoice,
      where: c.stripe_invoice_id in ^stripe_invoice_ids,
      select: {c.stripe_invoice_id, c.source}
    )
    |> Repo.all()
    |> Map.new(fn {id, source} -> {id, Map.get(@credit_sources, source, :unknown)} end)
  end

  # ─── Clients ─────────────────────────────────────────────────────────────

  defp build_clients(data, as_of) do
    clients = base_clients(data, as_of)
    context = client_context(data, Enum.map(clients, & &1.user_id), as_of)

    clients
    |> Enum.map(&with_context(&1, context))
    |> Enum.sort_by(&{-&1.mrr, &1.email || ""})
  end

  # What the client list shows beyond revenue: subscription, payments, log and usage.
  defp client_context(data, user_ids, as_of) do
    {api_calls, last_active} = usage(user_ids, as_of, data.settings)

    %{
      subscriptions: subscriptions_by_user(user_ids, Map.keys(data.plans)),
      failed_invoices: users_with_failed_invoices(user_ids, data.users, Map.keys(data.plans)),
      status: manual_status_by_user(data.entries_by_user, user_ids, as_of),
      retention: retention_users(data.entries_by_user, user_ids, as_of, data.settings),
      api_calls: api_calls,
      last_active: last_active,
      overrides: data.overrides
    }
  end

  defp with_context(client, context) do
    id = client.user_id
    subscription = Map.get(context.subscriptions, id)
    sub_status = subscription && subscription.status
    {manual_status, open_count} = Map.get(context.status, id, {:healthy, 0})
    {calls, calls_prev} = context.api_calls.(id)

    client
    |> Map.merge(%{
      subscription_status: sub_status,
      renewal_date: renewal_date(subscription, client),
      failed_payment?:
        sub_status in @failed_statuses or MapSet.member?(context.failed_invoices, id),
      api_calls: calls,
      api_calls_prev: calls_prev,
      last_active_at: Map.get(context.last_active, id),
      manual_status: manual_status,
      open_entries_count: open_count,
      retention_action?: MapSet.member?(context.retention, id),
      override: Map.get(context.overrides, id)
    })
    |> Map.delete(:last_period_end)
  end

  # The revenue part of every client active on `as_of`.
  defp base_clients(data, as_of) do
    for {user_id, lines} <- data.lines_by_user,
        current = Periods.current_lines(lines, as_of),
        current != [] do
      user = Map.get(data.users, user_id, @unknown_user)
      # The line paying the most names the client's plan.
      main = Enum.max_by(current, &Periods.monthly_value/1)

      %{
        user_id: user_id,
        email: user.email,
        username: user.username,
        stripe_customer_id: user.stripe_customer_id,
        plan_name: main.plan_name,
        product_id: main.product_id,
        interval: main.interval,
        business_reason: business_reason(current, Map.get(data.overrides, user_id))
      }
      |> Map.merge(revenue(lines, current, as_of, data.credit_sources))
    end
  end

  defp revenue(lines, current, as_of, credit_sources) do
    mrr = current |> Enum.map(&Periods.monthly_value/1) |> Enum.sum()
    countable = Enum.filter(lines, &Periods.countable?/1)
    to_date = Enum.filter(lines, &invoiced_by?(&1, as_of))

    %{
      mrr: mrr,
      acv: mrr * 12,
      tcv: to_date |> Enum.map(& &1.amount) |> Enum.sum(),
      start_date: countable |> Enum.map(& &1.period_start) |> Enum.min(Date),
      last_period_end: countable |> Enum.map(& &1.period_end) |> Enum.max(Date),
      paid_by: paid_by(to_date, credit_sources)
    }
  end

  defp invoiced_by?(%{invoiced_at: %DateTime{} = at}, as_of),
    do: Date.compare(DateTime.to_date(at), as_of) != :gt

  defp invoiced_by?(_line, _as_of), do: true

  defp business_reason(current, override) do
    cond do
      Enum.any?(current, &(&1.kind == :business)) -> :plan
      override == true -> :override
      true -> :business_email
    end
  end

  # Lifetime business revenue by payment method. Each invoice's business amount is
  # split between card and credit in proportion to `amount_paid` and `credit_applied`.
  defp paid_by(lines, credit_sources) do
    empty = Map.new(@paid_by_keys, &{&1, 0})

    lines
    |> Enum.group_by(& &1.invoice_id)
    |> Enum.reduce(empty, fn {_invoice_id, [invoice | _] = invoice_lines}, acc ->
      amount = invoice_lines |> Enum.map(& &1.amount) |> Enum.sum()
      credit_source = Map.get(credit_sources, invoice.stripe_invoice_id)

      invoice
      |> split_payment(amount, credit_source)
      |> Enum.reduce(acc, fn {source, cents}, acc -> Map.update!(acc, source, &(&1 + cents)) end)
    end)
  end

  defp split_payment(invoice, amount, credit_source) do
    paid = invoice.amount_paid
    credit = invoice.credit_applied

    cond do
      invoice.paid_out_of_band and credit_source not in [nil, :unknown] ->
        [{credit_source, amount}]

      invoice.paid_out_of_band ->
        [{:out_of_band, amount}]

      credit > 0 and paid + credit > 0 ->
        credit_part = round(amount * credit / (paid + credit))
        [{:card, amount - credit_part}, {credit_source || :unknown, credit_part}]

      paid > 0 ->
        [{:card, amount}]

      true ->
        [{:unknown, amount}]
    end
  end

  # The newest subscription on a business plan per user, a live one first.
  defp subscriptions_by_user([], _plan_ids), do: %{}

  defp subscriptions_by_user(user_ids, plan_ids) do
    from(s in Subscription,
      where: s.user_id in ^user_ids and s.plan_id in ^plan_ids,
      order_by: [desc: s.id],
      select: %{user_id: s.user_id, status: s.status, current_period_end: s.current_period_end}
    )
    |> Repo.all()
    |> Enum.group_by(& &1.user_id)
    |> Map.new(fn {user_id, subscriptions} ->
      {user_id, Enum.find(subscriptions, hd(subscriptions), &(&1.status in @live_statuses))}
    end)
  end

  defp renewal_date(%{status: status, current_period_end: %DateTime{} = end_at}, _client)
       when status in @live_statuses,
       do: DateTime.to_date(end_at)

  defp renewal_date(_subscription, client), do: client.last_period_end

  # Users with a business invoice left unpaid: open or uncollectible past the first
  # retries, with a line on one of the plans. An unpaid invoice for something else is
  # not a failed payment of the client.
  defp users_with_failed_invoices([], _users, _plan_ids), do: MapSet.new()

  defp users_with_failed_invoices(user_ids, users, plan_ids) do
    cutoff = DateTime.add(DateTime.utc_now(), -@failed_payment_after_days, :day)

    customer_to_user =
      for id <- user_ids,
          customer = get_in(users, [id, :stripe_customer_id]),
          customer != nil,
          into: %{},
          do: {customer, id}

    customer_ids = Map.keys(customer_to_user)

    business_line =
      from([line: l, price_plan: p] in lines_with_plan(),
        where: l.invoice_id == parent_as(:invoice).id and coalesce(l.plan_id, p.id) in ^plan_ids,
        select: 1
      )

    from(i in Invoice,
      as: :invoice,
      where: i.status in ["open", "uncollectible"] and i.invoiced_at < ^cutoff,
      where: i.user_id in ^user_ids or i.stripe_customer_id in ^customer_ids,
      where: exists(business_line),
      select: {i.user_id, i.stripe_customer_id}
    )
    |> Repo.all()
    |> Enum.map(fn {user_id, customer} -> user_id || Map.get(customer_to_user, customer) end)
    |> MapSet.new()
  end

  # `{manual_status, open entry count}` per user, from the entries open on `as_of`.
  defp manual_status_by_user(entries_by_user, user_ids, as_of) do
    for user_id <- user_ids,
        open = Enum.filter(Map.get(entries_by_user, user_id, []), &open_on?(&1, as_of)),
        open != [],
        into: %{},
        do: {user_id, {BusinessClients.manual_status(open), length(open)}}
  end

  # Users with an entry of the retention action type written by `as_of`.
  defp retention_users(entries_by_user, user_ids, as_of, settings) do
    type = settings.retention_action_type

    for user_id <- user_ids,
        entries = Map.get(entries_by_user, user_id, []),
        Enum.any?(entries, &(&1.type == type and written_by?(&1, as_of))),
        into: MapSet.new(),
        do: user_id
  end

  # Today an entry is open until resolved; on a past date, when it was written by then
  # and not yet resolved.
  defp open_on?(entry, as_of) do
    cond do
      current?(as_of) -> is_nil(entry.resolved_at)
      not written_by?(entry, as_of) -> false
      is_nil(entry.resolved_at) -> true
      true -> DateTime.compare(entry.resolved_at, end_of_day(as_of)) != :lt
    end
  end

  defp written_by?(entry, as_of) do
    current?(as_of) or DateTime.compare(entry.inserted_at, end_of_day(as_of)) == :lt
  end

  # Returns a lookup of `{calls, previous calls}` per user and the last web activity.
  # When the ClickHouse query returned nothing - failed, or nobody called - the counts
  # are `nil` rather than a misleading 0.
  defp usage([], _as_of, _settings), do: {fn _ -> {nil, nil} end, %{}}

  defp usage(user_ids, as_of, settings) do
    until = if current?(as_of), do: DateTime.utc_now(), else: end_of_day(as_of)
    calls = Usage.api_calls_two_windows(user_ids, settings.usage_window_days, until)

    lookup =
      if calls == %{},
        do: fn _ -> {nil, nil} end,
        else: &Map.get(calls, &1, {0, 0})

    {lookup, Usage.last_web_activity(user_ids)}
  end

  # ─── Metrics ─────────────────────────────────────────────────────────────

  defp metrics_for(data, as_of) do
    settings = data.settings
    window = settings.churn_window_months
    clients = base_clients(data, as_of)
    user_ids = Enum.map(clients, & &1.user_id)
    status = manual_status_by_user(data.entries_by_user, user_ids, as_of)

    at_risk =
      for {user_id, {manual_status, _count}} <- status, manual_status != :healthy, do: user_id

    retention = retention_users(data.entries_by_user, at_risk, as_of, settings)
    churn = Periods.churn(data.lines_by_user, as_of, window)

    renewal =
      Periods.renewal(data.lines_by_user, as_of,
        window_months: window,
        intervals: settings.renewal_intervals,
        grace_days: settings.renewal_grace_days,
        upgrades_full_value: settings.renewal_upgrades_full_value
      )

    %{
      as_of: as_of,
      window: %{from: Periods.months_before(as_of, window), to: as_of},
      client_count: length(clients),
      at_risk_count: length(at_risk),
      retention_action_pct:
        if(at_risk == [], do: nil, else: MapSet.size(retention) / length(at_risk) * 100),
      client_churn: churn.client,
      revenue_churn: churn.revenue,
      client_renewal: renewal.client,
      revenue_renewal: renewal.revenue,
      settings: settings
    }
  end

  # ─── Invoices ────────────────────────────────────────────────────────────

  defp invoices_of(user_id) do
    customer_id =
      from(u in User, where: u.id == ^user_id, select: u.stripe_customer_id) |> Repo.one()

    query =
      if customer_id,
        do:
          from(i in Invoice, where: i.user_id == ^user_id or i.stripe_customer_id == ^customer_id),
        else: from(i in Invoice, where: i.user_id == ^user_id)

    invoices =
      from(i in query,
        order_by: [desc: i.invoiced_at, desc: i.id],
        preload: [lines: ^from(l in InvoiceLine, order_by: l.id, preload: :plan)]
      )
      |> Repo.all()

    sources = credit_sources(Enum.map(invoices, & &1.stripe_invoice_id))

    Enum.map(invoices, fn invoice ->
      %{
        stripe_invoice_id: invoice.stripe_invoice_id,
        invoice_number: invoice.invoice_number,
        invoiced_at: invoice.invoiced_at,
        status: invoice.status,
        total_excluding_tax: invoice.total_excluding_tax,
        amount_paid: invoice.amount_paid,
        credit_applied: invoice.credit_applied,
        paid_out_of_band: invoice.paid_out_of_band,
        source: invoice_source(invoice, Map.get(sources, invoice.stripe_invoice_id)),
        lines:
          Enum.map(invoice.lines, fn line ->
            %{
              plan_name: line.plan && line.plan.name,
              period_start: line.period_start,
              period_end: line.period_end,
              amount_excluding_tax: line.amount_excluding_tax,
              proration: line.proration
            }
          end)
      }
    end)
  end

  # The one method that paid most of the invoice; `:none` when nothing was paid.
  defp invoice_source(invoice, credit_source) do
    cond do
      invoice.paid_out_of_band and credit_source not in [nil, :unknown] ->
        credit_source

      invoice.paid_out_of_band ->
        :out_of_band

      invoice.credit_applied > 0 and invoice.credit_applied >= invoice.amount_paid ->
        credit_source || :unknown

      invoice.amount_paid > 0 ->
        :card

      true ->
        :none
    end
  end

  # ─── Helpers ─────────────────────────────────────────────────────────────

  defp current?(as_of), do: Date.compare(as_of, Date.utc_today()) != :lt

  defp end_of_day(date), do: DateTime.new!(Date.add(date, 1), ~T[00:00:00], "Etc/UTC")

  defp to_date(nil), do: nil
  defp to_date(%DateTime{} = datetime), do: DateTime.to_date(datetime)
end
