defmodule Sanbase.Billing.BusinessClients.ReportTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Billing.BusinessClients
  alias Sanbase.Billing.BusinessClients.{Report, Snapshots}
  alias Sanbase.Billing.CreditPayments.CreditInvoice
  alias Sanbase.Billing.InvoiceMirror.{Invoice, InvoiceLine, SyncRun}
  alias Sanbase.Billing.Plan
  alias Sanbase.Repo

  @business_pro_monthly 107
  @business_pro_yearly 108
  @business_max_monthly 109
  @sanbase_pro 201
  @sanbase_pro_yearly 202
  @sanbase_basic 205

  setup do
    Sanbase.Billing.TestSeed.seed_products_and_plans()
    today = Date.utc_today()

    %{today: today}
  end

  # ─── Helpers ─────────────────────────────────────────────────────────────

  defp user(email, attrs \\ []), do: insert(:user, Keyword.merge([email: email], attrs))

  defp at(%Date{} = date), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")

  # An invoice with the given lines: `{plan_id, period_start, period_end, amount}` or
  # with a fourth-element keyword list of line options.
  defp invoice(user, lines, attrs \\ []) do
    n = System.unique_integer([:positive])
    first_start = lines |> hd() |> elem(1)
    total = lines |> Enum.map(&(elem(&1, 3) - line_discount(&1))) |> Enum.sum()

    invoice =
      Repo.insert!(
        struct(
          %Invoice{
            stripe_invoice_id: "in_#{n}",
            invoice_number: "SAN-#{n}",
            user_id: user.id,
            stripe_customer_id: user.stripe_customer_id,
            stripe_subscription_id: Keyword.get(attrs, :subscription, "sub_#{user.id}"),
            status: "paid",
            currency: "usd",
            invoiced_at: at(first_start),
            total: total,
            total_excluding_tax: total,
            amount_paid: max(total, 0),
            synced_at: DateTime.utc_now() |> DateTime.truncate(:second)
          },
          Keyword.drop(attrs, [:subscription])
        )
      )

    for line <- lines do
      {plan_id, from, to, amount, opts} =
        case line do
          {p, f, t, a} -> {p, f, t, a, []}
          {p, f, t, a, o} -> {p, f, t, a, o}
        end

      Repo.insert!(%InvoiceLine{
        invoice_id: invoice.id,
        stripe_line_id: "il_#{System.unique_integer([:positive])}",
        plan_id: plan_id,
        stripe_price_id: Keyword.get(opts, :price),
        period_start: at(from),
        period_end: at(to),
        amount: amount,
        amount_excluding_tax: amount,
        discount: Keyword.get(opts, :discount, 0),
        proration: Keyword.get(opts, :proration, false)
      })
    end

    invoice
  end

  defp line_discount({_, _, _, _, opts}), do: Keyword.get(opts, :discount, 0)
  defp line_discount(_line), do: 0

  defp with_usage(rows, fun) do
    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fun)
  end

  defp list_clients(opts \\ []), do: with_usage([], fn -> Report.list_clients(opts) end)

  defp month_ago(today, months), do: Date.shift(today, month: -months)

  # ─── list_clients/1 ──────────────────────────────────────────────────────

  describe "list_clients/1" do
    test "a business plan counts whatever the email, with ACV and TCV", %{today: today} do
      user = user("someone@gmail.com")
      start = Date.add(today, -100)

      invoice(user, [{@business_pro_yearly, start, Date.shift(start, year: 1), 478_800}])

      invoice(user, [
        {@business_pro_yearly, Date.add(today, -10), Date.shift(start, year: 1), 5_000,
         [proration: true]}
      ])

      assert [client] = list_clients()
      assert client.user_id == user.id
      assert client.business_reason == :plan
      assert client.plan_name == "BUSINESS_PRO"
      assert client.interval == "year"
      assert client.mrr == 39_900
      assert client.acv == 478_800
      assert client.tcv == 483_800
      assert client.start_date == start
      assert client.renewal_date == Date.shift(start, year: 1)
      assert client.paid_by.card == 483_800
      assert client.manual_status == :healthy
      assert client.failed_payment? == false
      assert client.unpaid_invoice? == false
      assert client.override == nil
    end

    test "a Sanbase PRO plan counts only with a business email or an override",
         %{today: today} do
      period = {Date.add(today, -5), Date.add(today, 25)}

      business = user("ceo@fund.io")
      free = user("someone@gmail.com")
      overridden = user("trader@gmail.com")
      vetoed = user("cto@company.com")
      basic = user("ops@company.com")

      for u <- [business, free, overridden, vetoed],
          do: invoice(u, [{@sanbase_pro, elem(period, 0), elem(period, 1), 4_900}])

      invoice(basic, [{@sanbase_basic, elem(period, 0), elem(period, 1), 2_500}])

      {:ok, _} = BusinessClients.set_override(overridden.id, true, nil)
      {:ok, _} = BusinessClients.set_override(vetoed.id, false, nil)

      reasons = list_clients() |> Map.new(&{&1.user_id, &1.business_reason})

      assert reasons == %{business.id => :business_email, overridden.id => :override}
    end

    test "team accounts, unpaid invoices, $0 and expired lines are left out", %{today: today} do
      team = user("dev@santiment.net")
      unpaid = user("a@corp.com")
      zero = user("b@corp.com")
      expired = user("c@corp.com")

      invoice(team, [{@business_max_monthly, Date.add(today, -5), Date.add(today, 25), 99_900}])

      invoice(unpaid, [{@business_max_monthly, Date.add(today, -5), Date.add(today, 25), 99_900}],
        status: "open"
      )

      invoice(zero, [{@business_max_monthly, Date.add(today, -5), Date.add(today, 25), 0}])

      invoice(expired, [
        {@business_max_monthly, Date.add(today, -40), Date.add(today, -10), 99_900}
      ])

      assert list_clients() == []
    end

    test "sorted by MRR, highest first", %{today: today} do
      small = user("small@corp.com")
      big = user("big@corp.com")

      invoice(small, [{@business_pro_monthly, Date.add(today, -5), Date.add(today, 25), 42_000}])
      invoice(big, [{@business_max_monthly, Date.add(today, -5), Date.add(today, 25), 99_900}])

      assert Enum.map(list_clients(), & &1.user_id) == [big.id, small.id]
    end

    test "payment sources: credit, out of band and an unpaid invoice", %{today: today} do
      user = user("fin@corp.com", stripe_customer_id: "cus_fin")
      start = Date.add(today, -70)

      crypto =
        invoice(user, [{@business_pro_monthly, start, Date.add(start, 30), 42_000}],
          amount_paid: 0,
          credit_applied: 42_000
        )

      Repo.insert!(%CreditInvoice{
        stripe_invoice_id: crypto.stripe_invoice_id,
        invoiced_at: crypto.invoiced_at,
        source: "crypto",
        synced_at: crypto.synced_at
      })

      invoice(
        user,
        [{@business_pro_monthly, Date.add(start, 30), Date.add(start, 60), 42_000}],
        amount_paid: 21_000,
        credit_applied: 21_000
      )

      invoice(
        user,
        [{@business_pro_monthly, Date.add(start, 60), Date.add(start, 90), 42_000}],
        amount_paid: 0,
        paid_out_of_band: true
      )

      invoice(user, [{@business_pro_monthly, Date.add(today, -20), Date.add(today, 10), 1}],
        status: "open"
      )

      assert [client] = list_clients()
      assert client.paid_by.crypto == 42_000
      assert client.paid_by.card == 21_000
      assert client.paid_by.unknown == 21_000
      assert client.paid_by.out_of_band == 42_000
      assert client.tcv == 126_000
      # An open invoice - e.g. wire or crypto not received yet - is not a failed charge.
      assert client.unpaid_invoice?
      refute client.failed_payment?
    end

    test "an uncollectible invoice followed by a paid one is settled, an open one is not",
         %{today: today} do
      user = user("trial@corp.com")
      start = Date.add(today, -60)

      invoice(user, [{@business_pro_monthly, start, Date.add(start, 30), 42_000}],
        status: "uncollectible",
        subscription: "sub_monthly"
      )

      invoice(user, [{@business_pro_yearly, Date.add(start, 25), Date.add(start, 390), 478_800}])

      assert [%{unpaid_invoice?: false, tcv: 478_800}] = list_clients()

      invoice(user, [{@business_pro_monthly, Date.add(today, -15), Date.add(today, 15), 42_000}],
        status: "open",
        subscription: "sub_monthly"
      )

      assert [%{unpaid_invoice?: true}] = list_clients()
    end

    test "revenue is counted after discounts and a fully discounted line does not count",
         %{today: today} do
      user = user("coupon@corp.com")
      comped = user("comped@corp.com")
      start = Date.add(today, -100)

      invoice(user, [
        {@business_pro_yearly, start, Date.shift(start, year: 1), 478_800, [discount: 47_880]}
      ])

      invoice(comped, [
        {@business_pro_yearly, start, Date.shift(start, year: 1), 478_800, [discount: 478_800]}
      ])

      assert [client] = list_clients()
      assert client.user_id == user.id
      assert client.acv == 430_920
      assert client.tcv == 430_920

      assert client.mrr ==
               Sanbase.Billing.BusinessClients.Periods.monthly_value(%{
                 amount: 430_920,
                 period_start: start,
                 period_end: Date.shift(start, year: 1)
               })
    end

    test "a past due business subscription is a failed payment", %{today: today} do
      user = user("late@payer.com")
      invoice(user, [{@business_pro_monthly, Date.add(today, -5), Date.add(today, 25), 42_000}])

      insert(:subscription_pro_sanbase,
        user: user,
        plan_id: @business_pro_monthly,
        status: :past_due
      )

      assert [client] = list_clients()
      assert client.subscription_status == :past_due
      assert client.failed_payment?
      refute client.unpaid_invoice?
    end

    test "a line without a plan id counts by its Stripe price", %{today: today} do
      user = user("late@corp.com")

      Repo.update_all(from(p in Plan, where: p.id == @business_pro_monthly),
        set: [stripe_id: "price_business_pro"]
      )

      invoice(user, [
        {nil, Date.add(today, -5), Date.add(today, 25), 42_000, [price: "price_business_pro"]}
      ])

      assert [%{user_id: id, plan_name: "BUSINESS_PRO", mrr: 42_000}] = list_clients()
      assert id == user.id
    end

    test "an unpaid invoice of another plan is not a failed payment", %{today: today} do
      user = user("ok@corp.com")
      invoice(user, [{@business_pro_monthly, Date.add(today, -5), Date.add(today, 25), 42_000}])

      invoice(user, [{@sanbase_basic, Date.add(today, -20), Date.add(today, 10), 2_500}],
        status: "open",
        subscription: "sub_other"
      )

      assert [%{failed_payment?: false, unpaid_invoice?: false}] = list_clients()
    end

    test "manual status, retention and usage", %{today: today} do
      user = user("risk@corp.com")
      author = user("admin@santiment.net")
      invoice(user, [{@business_pro_monthly, Date.add(today, -5), Date.add(today, 25), 42_000}])

      {:ok, _} =
        BusinessClients.create_entry(user.id, author.id, %{type: "Complaint", severity: "at_risk"})

      {:ok, _} =
        BusinessClients.create_entry(user.id, author.id, %{type: "Retention action"})

      assert [client] =
               with_usage([[user.id, 120, 80]], fn -> Report.list_clients() end)

      assert client.manual_status == :at_risk
      assert client.open_entries_count == 2
      assert client.retention_action?
      assert client.api_calls == 120
      assert client.api_calls_prev == 80
    end

    test "last active is the later of the last web session and the last API call",
         %{today: today} do
      web_user = user("web@corp.com")
      api_user = user("api@corp.com")

      for u <- [web_user, api_user],
          do:
            invoice(u, [{@business_pro_monthly, Date.add(today, -5), Date.add(today, 25), 42_000}])

      # A web session now for one; only API calls for the other.
      {:ok, _tokens} = SanbaseWeb.Guardian.get_jwt_tokens(web_user)
      week_ago = DateTime.utc_now() |> DateTime.add(-7, :day) |> DateTime.truncate(:second)
      yesterday = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)

      clients =
        Sanbase.Mock.prepare_mock(Sanbase.ClickhouseRepo, :query, fn sql, _args, _opts ->
          if sql =~ "max(dt)" do
            {:ok,
             %{
               rows: [
                 [web_user.id, DateTime.to_unix(week_ago)],
                 [api_user.id, DateTime.to_unix(yesterday)]
               ]
             }}
          else
            {:ok, %{rows: []}}
          end
        end)
        |> Sanbase.Mock.run_with_mocks(fn -> Report.list_clients() end)
        |> Map.new(&{&1.user_id, &1})

      web = clients[web_user.id]
      assert web.last_api_call_at == week_ago
      assert %DateTime{} = web.last_web_active_at
      assert DateTime.compare(web.last_web_active_at, week_ago) == :gt
      assert web.last_active_at == web.last_web_active_at

      api = clients[api_user.id]
      assert api.last_web_active_at == nil
      assert api.last_api_call_at == yesterday
      assert api.last_active_at == yesterday
    end

    test "past as_of uses the lines of that date", %{today: today} do
      user = user("old@corp.com")
      invoice(user, [{@business_pro_monthly, Date.add(today, -70), Date.add(today, -40), 42_000}])

      assert list_clients() == []
      assert [%{user_id: id}] = list_clients(as_of: Date.add(today, -50))
      assert id == user.id
    end
  end

  # ─── metrics/1 ───────────────────────────────────────────────────────────

  describe "metrics/1" do
    test "churn and renewal over the window", %{today: today} do
      stays = user("stays@corp.com")
      leaves = user("leaves@corp.com")
      author = user("admin@santiment.net")

      year_ago = Date.add(month_ago(today, 12), -40)
      invoice(stays, [{@business_pro_yearly, year_ago, Date.shift(year_ago, year: 1), 478_800}])

      renewed_on = Date.shift(year_ago, year: 1)

      invoice(stays, [
        {@business_pro_yearly, renewed_on, Date.shift(renewed_on, year: 1), 478_800}
      ])

      invoice(leaves, [{@business_pro_yearly, year_ago, Date.shift(year_ago, year: 1), 478_800}])

      {:ok, _} =
        BusinessClients.create_entry(stays.id, author.id, %{
          type: "Complaint",
          severity: "high_risk"
        })

      metrics = Report.metrics()

      assert metrics.as_of == today
      assert metrics.window == %{from: month_ago(today, 12), to: today}
      assert metrics.client_count == 1
      assert metrics.at_risk_count == 1
      assert metrics.retention_action_pct == 0.0
      assert metrics.client_churn == %{rate: 0.5, lost: 1, base: 2}
      assert metrics.revenue_churn.rate == 0.5
      assert metrics.client_renewal == %{rate: 0.5, renewed: 1, due: 2}
      assert metrics.revenue_renewal.rate == 0.5
      assert metrics.settings.churn_window_months == 12
    end

    test "segments: counts by today's segment, churn by the cohort date's, renewal by the due line",
         %{today: today} do
      cohort_date = month_ago(today, 12)
      year_ago = Date.add(cohort_date, -40)
      author = user("admin@santiment.net")

      # An email plan a year ago, a business plan now: in the email cohort, not lost.
      switcher = user("switch@corp.com")

      invoice(switcher, [
        {@sanbase_pro, Date.add(cohort_date, -5), Date.add(cohort_date, 25), 4_900}
      ])

      invoice(switcher, [
        {@business_pro_monthly, Date.add(today, -5), Date.add(today, 25), 42_000}
      ])

      # A business plan year renewed: plan cohort, plan renewal.
      plan_stays = user("stays@corp.com")

      invoice(plan_stays, [
        {@business_pro_yearly, year_ago, Date.shift(year_ago, year: 1), 478_800}
      ])

      renewed_on = Date.shift(year_ago, year: 1)

      invoice(plan_stays, [
        {@business_pro_yearly, renewed_on, Date.shift(renewed_on, year: 1), 478_800}
      ])

      # An email-plan year not renewed: email cohort lost, email renewal due.
      email_leaves = user("leaves@fund.io")

      invoice(email_leaves, [
        {@sanbase_pro_yearly, year_ago, Date.shift(year_ago, year: 1), 52_900}
      ])

      # A new email-plan client, at risk.
      email_new = user("new@fund.io")
      invoice(email_new, [{@sanbase_pro, Date.add(today, -5), Date.add(today, 25), 4_900}])

      {:ok, _} =
        BusinessClients.create_entry(email_new.id, author.id, %{
          type: "Complaint",
          severity: "high_risk"
        })

      metrics = Report.metrics()
      %{plan: plan, business_email: email} = metrics.segments

      assert {metrics.client_count, plan.client_count, email.client_count} == {3, 2, 1}
      assert metrics.mrr == plan.mrr + email.mrr
      assert email.mrr == 4_900
      assert {metrics.at_risk_count, plan.at_risk_count, email.at_risk_count} == {1, 0, 1}
      assert plan.retention_action_pct == nil
      assert email.retention_action_pct == 0.0

      # The switcher counts where they were a year ago.
      assert metrics.client_churn == %{rate: 1 / 3, lost: 1, base: 3}
      assert plan.client_churn == %{rate: 0.0, lost: 0, base: 1}
      assert email.client_churn == %{rate: 0.5, lost: 1, base: 2}

      for key <- [:base_mrr, :lost_mrr, :expansion_mrr] do
        assert Map.fetch!(plan.revenue_churn, key) + Map.fetch!(email.revenue_churn, key) ==
                 Map.fetch!(metrics.revenue_churn, key)
      end

      assert metrics.client_renewal == %{rate: 0.5, renewed: 1, due: 2}
      assert plan.client_renewal == %{rate: 1.0, renewed: 1, due: 1}
      assert email.client_renewal == %{rate: 0.0, renewed: 0, due: 1}

      assert plan.revenue_renewal.due_acv + email.revenue_renewal.due_acv ==
               metrics.revenue_renewal.due_acv

      assert Map.keys(plan) ==
               Map.keys(Map.drop(metrics, [:as_of, :window, :segments, :settings]))
    end
  end

  # ─── churned_clients/1 ───────────────────────────────────────────────────

  describe "churned_clients/1" do
    test "who left within the window, latest first", %{today: today} do
      left = user("left@corp.com", username: "lefty", stripe_customer_id: "cus_left")
      brief = user("brief@corp.com")
      active = user("active@corp.com")
      before = user("before@corp.com")
      switched = user("switched@corp.com")
      team = user("gone@santiment.net")
      author = user("admin@santiment.net")

      joined = Date.add(today, -400)
      invoice(left, [{@business_pro_yearly, joined, Date.add(joined, 365), 478_800}])

      invoice(left, [
        {@business_max_monthly, Date.add(today, -65), Date.add(today, -35), 99_900}
      ])

      # Joined and left within the window.
      invoice(brief, [
        {@business_pro_monthly, Date.add(today, -100), Date.add(today, -70), 42_000}
      ])

      invoice(active, [
        {@business_pro_monthly, Date.add(today, -100), Date.add(today, -70), 42_000}
      ])

      invoice(active, [{@business_pro_monthly, Date.add(today, -5), Date.add(today, 25), 42_000}])

      invoice(before, [
        {@business_pro_monthly, Date.add(month_ago(today, 12), -40),
         Date.add(month_ago(today, 12), -10), 42_000}
      ])

      # A plan switch, on a new subscription: still a client.
      invoice(switched, [
        {@business_pro_monthly, Date.add(today, -40), Date.add(today, -10), 42_000}
      ])

      invoice(
        switched,
        [{@business_max_monthly, Date.add(today, -10), Date.add(today, 20), 99_900}],
        subscription: "sub_switched_new"
      )

      invoice(team, [{@business_pro_monthly, Date.add(today, -60), Date.add(today, -30), 42_000}])

      long_note = String.duplicate("x", 200)

      {:ok, _} =
        BusinessClients.create_entry(left.id, author.id, %{type: "Complaint", note: long_note})

      assert [left_row, brief_row] = Report.churned_clients(as_of: today)

      assert left_row.user_id == left.id
      assert left_row.email == "left@corp.com"
      assert left_row.username == "lefty"
      assert left_row.stripe_customer_id == "cus_left"
      assert left_row.business_reason == :plan
      assert left_row.last_plan_name == "BUSINESS_MAX"
      assert left_row.interval == "month"
      assert left_row.joined_on == joined
      assert left_row.churned_on == Date.add(today, -35)
      assert left_row.lost_mrr == 99_900
      assert left_row.tcv == 478_800 + 99_900
      assert left_row.current_subscription == nil
      assert left_row.last_entry.type == "Complaint"
      assert left_row.last_entry.note == String.duplicate("x", 120)

      assert brief_row.user_id == brief.id
      assert brief_row.churned_on == Date.add(today, -70)
      assert brief_row.joined_on == Date.add(today, -100)
      assert brief_row.lost_mrr == 42_000
      assert brief_row.last_entry == nil
    end

    test "shows a current subscription on any plan, including a bundle", %{today: today} do
      to_bundle = user("bundle@corp.com")
      to_pro = user("pro@corp.com")

      for u <- [to_bundle, to_pro],
          do:
            invoice(u, [
              {@business_pro_monthly, Date.add(today, -60), Date.add(today, -30), 42_000}
            ])

      bundle =
        insert(:plan_pro,
          id: 9_901,
          name: "BUNDLE",
          product_id: 1,
          amount: 0,
          is_private: true,
          stripe_id: "plan_bundle_#{System.unique_integer([:positive])}"
        )

      insert(:subscription_pro_sanbase, user: to_bundle, plan_id: bundle.id)
      insert(:subscription_pro_sanbase, user: to_pro, plan_id: @sanbase_pro)
      insert(:subscription_pro_sanbase, user: to_pro, plan_id: @sanbase_basic, status: :canceled)

      rows = Report.churned_clients(as_of: today) |> Map.new(&{&1.user_id, &1})

      assert rows[to_bundle.id].current_subscription == "BUNDLE"
      assert rows[to_pro.id].current_subscription == "PRO"
    end
  end

  # ─── page/1 ──────────────────────────────────────────────────────────────

  describe "page/1" do
    test "equals the separate calls, for today and a past date", %{today: today} do
      stays = user("stays@corp.com")
      leaves = user("leaves@corp.com")
      author = user("admin@santiment.net")

      invoice(stays, [{@business_pro_monthly, Date.add(today, -100), Date.add(today, 25), 42_000}])

      invoice(leaves, [
        {@business_max_monthly, Date.add(today, -90), Date.add(today, -30), 99_900}
      ])

      {:ok, entry} =
        BusinessClients.create_entry(leaves.id, author.id, %{
          type: "Complaint",
          severity: "high_risk"
        })

      Repo.update_all(from(e in BusinessClients.LogEntry, where: e.id == ^entry.id),
        set: [inserted_at: at(Date.add(today, -60))]
      )

      {:ok, _} =
        BusinessClients.create_entry(stays.id, author.id, %{type: "Retention action"})

      past = Date.add(today, -45)

      with_usage([], fn ->
        for as_of <- [today, past] do
          page = Report.page(as_of: as_of, months: 3)

          assert page == %{
                   clients: Report.list_clients(as_of: as_of),
                   churned: Report.churned_clients(as_of: as_of),
                   metrics: Report.metrics(as_of: as_of),
                   monthly: Report.monthly_metrics(months: 3)
                 }
        end

        # On the past date the complaint was open and the retention entry not yet written.
        assert %{clients: clients, metrics: metrics} = Report.page(as_of: past)
        assert %{manual_status: :high_risk} = Enum.find(clients, &(&1.user_id == leaves.id))
        assert %{retention_action?: false} = Enum.find(clients, &(&1.user_id == stays.id))
        assert metrics.at_risk_count == 1
      end)
    end
  end

  # ─── Snapshots and monthly_metrics/1 ─────────────────────────────────────

  describe "snapshots" do
    test "take/1 is idempotent and monthly_metrics/1 reads it back", %{today: today} do
      user = user("snap@corp.com")
      month = Date.beginning_of_month(today)
      invoice(user, [{@business_pro_monthly, Date.add(month, -5), Date.add(month, 25), 42_000}])

      with_usage([], fn ->
        assert {:ok, %{clients: 1, metrics: true}} = Snapshots.take(today)
        assert {:ok, %{clients: 0, metrics: false}} = Snapshots.take(today)
      end)

      [current, previous | _] = monthly_metrics = Report.monthly_metrics(months: 3)

      assert length(monthly_metrics) == 3
      assert current.month == month
      assert current.source == :snapshot
      assert current.client_count == 1
      assert current.as_of == month
      assert current.client_churn == %{rate: nil, lost: 0, base: 0}
      assert current.settings.renewal_grace_days == 30
      assert current.segments.plan.client_count == 1
      assert current.segments.business_email.client_count == 0
      assert current.segments.plan.client_churn == %{rate: nil, lost: 0, base: 0}
      assert previous.source == :computed
      assert previous.month == Date.shift(month, month: -1)
    end
  end

  describe "Snapshots.metrics_from_data/1" do
    test "data stored before the segment split has no segments" do
      metrics =
        Snapshots.metrics_from_data(%{
          "as_of" => "2026-01-01",
          "window" => %{"from" => "2025-01-01", "to" => "2026-01-01"},
          "client_count" => 5,
          "mrr" => 120_000,
          "client_churn" => %{"rate" => 0.2, "lost" => 1, "base" => 5}
        })

      assert metrics.client_count == 5
      assert metrics.mrr == 120_000
      assert metrics.client_churn == %{rate: 0.2, lost: 1, base: 5}
      assert metrics.segments == nil
    end
  end

  describe "Snapshots.run/0" do
    test "skips the month while the invoice mirror has a gap", %{today: today} do
      user = user("gap@corp.com")
      month = Date.beginning_of_month(today)
      invoice(user, [{@business_pro_monthly, Date.add(month, -5), Date.add(month, 25), 42_000}])
      since = Date.shift(month, month: -1)

      with_usage([], fn ->
        assert {:error, :invoice_gap} = Snapshots.run()
        assert Repo.aggregate(BusinessClients.MetricsSnapshot, :count) == 0

        {:ok, _} = SyncRun.create(%{from_date: since, to_date: today, status: "completed"})

        assert :ok = Snapshots.run()
        assert Repo.aggregate(BusinessClients.MetricsSnapshot, :count) == 1
        assert Repo.aggregate(BusinessClients.ClientSnapshot, :count) == 1
      end)
    end
  end

  # ─── client_detail/1 ─────────────────────────────────────────────────────

  describe "client_detail/1" do
    test "the client, invoices newest first with lines, entries and override",
         %{today: today} do
      user = user("detail@corp.com")
      author = user("admin@santiment.net")
      invoice(user, [{@business_pro_monthly, Date.add(today, -35), Date.add(today, -5), 42_000}])
      invoice(user, [{@business_pro_monthly, Date.add(today, -5), Date.add(today, 25), 42_000}])
      {:ok, _} = BusinessClients.create_entry(user.id, author.id, %{type: "Other"})

      detail = with_usage([], fn -> Report.client_detail(user.id) end)

      assert detail.client.user_id == user.id
      assert detail.user == %{id: user.id, email: user.email, username: user.username}
      assert [newest, _older] = detail.invoices
      assert newest.source == :card
      assert [%{plan_name: "BUSINESS_PRO", amount_excluding_tax: 42_000}] = newest.lines
      assert [%{type: "Other"}] = detail.entries
      assert detail.override == nil
    end

    test "a user who is not a client" do
      user = user("nobody@corp.com")

      detail = with_usage([], fn -> Report.client_detail(user.id) end)

      assert detail.client == nil
      assert detail.invoices == []
    end
  end

  # ─── business_email_users/0 ──────────────────────────────────────────────

  describe "business_email_users/0" do
    test "only business domains, with the plan and whether they pay" do
      paying = user("boss@Fund.IO")
      free = user("someone@GMAIL.com")
      _team = user("dev@santiment.net")
      trial = user("trial@corp.com")

      insert(:subscription_pro_sanbase, user: paying)
      insert(:subscription_pro_sanbase, user: free)
      insert(:subscription_pro_sanbase, user: trial, status: :trialing)

      rows = Report.business_email_users() |> Map.new(&{&1.user_id, &1})

      assert Map.keys(rows) |> Enum.sort() == Enum.sort([paying.id, trial.id])
      assert %{plan_name: "PRO", paying?: true} = rows[paying.id]
      assert %{plan_name: "PRO", paying?: false} = rows[trial.id]
      refute Map.has_key?(rows, free.id)
    end
  end

  describe "formula_notes/1" do
    test "embeds the current parameters" do
      settings = %{BusinessClients.settings() | churn_window_months: 6, renewal_grace_days: 14}
      notes = Report.formula_notes(settings)

      assert notes.client_churn =~ "rolling 6 months"
      assert notes.client_renewal =~ "14-day grace"
      assert notes.churned =~ "rolling 6 months"

      assert Map.keys(notes) |> Enum.sort() ==
               Enum.sort(~w(business_client mrr acv tcv client_churn revenue_churn client_renewal
                            revenue_renewal at_risk retention churned usage)a)
    end
  end
end
