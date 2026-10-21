defmodule Sanbase.Billing.InvoiceMirror.SyncTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory

  alias Sanbase.Billing.InvoiceMirror
  alias Sanbase.Billing.InvoiceMirror.{Invoice, InvoiceLine, Sync, SyncJob, SyncRun}
  alias Sanbase.Billing.Plan
  alias Sanbase.Repo

  @today Date.utc_today()

  describe "sync_range/3" do
    test "writes the invoice and its lines, resolving the user and the plan", context do
      user = insert(:user, stripe_customer_id: "cus_test")
      plan = context.plans.plan_pro
      paid_at = DateTime.utc_now() |> DateTime.truncate(:second)

      invoice =
        invoice(
          status_transitions: %{paid_at: DateTime.to_unix(paid_at)},
          lines:
            lines([line(price: %{id: plan.stripe_id}), line(id: "il_2", price: "price_bundle")])
        )

      {:ok, summary} = sync([invoice])

      assert summary.invoices_upserted == 1
      assert summary.lines_upserted == 2

      assert [row] = Repo.all(Invoice)
      assert row.stripe_invoice_id == "in_test"
      assert row.invoice_number == "SAN-0001"
      assert row.user_id == user.id
      assert row.stripe_subscription_id == "sub_test"
      assert row.status == "paid"
      assert row.billing_reason == "subscription_cycle"
      assert row.paid_at == paid_at
      assert row.total == 12_000
      assert row.total_excluding_tax == 10_000
      assert row.tax == 2_000
      assert row.credit_applied == 0

      lines = Repo.all(from(l in InvoiceLine, order_by: l.stripe_line_id))
      assert [%{stripe_line_id: "il_1"} = with_plan, %{stripe_line_id: "il_2"} = bundle] = lines
      assert with_plan.plan_id == plan.id
      assert with_plan.invoice_id == row.id
      assert with_plan.period_start != nil
      assert bundle.stripe_price_id == "price_bundle"
      assert bundle.plan_id == nil
    end

    test "falls back to the billed email, an expanded subscription and the legacy plan" do
      user = insert(:user, email: "client@example.com")

      invoice =
        invoice(
          customer: "cus_unknown",
          customer_email: "Client@Example.com",
          subscription: %{id: "sub_expanded"},
          total_excluding_tax: nil,
          tax: nil,
          lines: lines([line(price: nil, plan: %{id: "plan_legacy"}, amount_excluding_tax: nil)])
        )

      {:ok, _summary} = sync([invoice])

      assert [row] = Repo.all(Invoice)
      assert row.user_id == user.id
      assert row.stripe_subscription_id == "sub_expanded"
      assert row.tax == 0
      assert row.total_excluding_tax == 12_000

      assert [line] = Repo.all(InvoiceLine)
      assert line.stripe_price_id == "plan_legacy"
      assert line.amount_excluding_tax == 10_000
    end

    test "drafts are skipped and every other status is kept" do
      invoices = [
        invoice(id: "in_draft", status: "draft"),
        invoice(id: "in_void", status: "void"),
        invoice(id: "in_open", status: "open")
      ]

      {:ok, summary} = sync(invoices)

      assert summary.invoices_upserted == 2

      assert Repo.all(from(i in Invoice, select: i.status, order_by: i.status)) == [
               "open",
               "void"
             ]
    end

    test "running it twice writes one invoice and replaces its lines" do
      {:ok, _} = sync([invoice(lines: lines([line(), line(id: "il_2")]))])
      {:ok, _} = sync([invoice(status: "void", lines: lines([line(id: "il_3")]))])

      assert [%{status: "void"}] = Repo.all(Invoice)
      assert Repo.all(from(l in InvoiceLine, select: l.stripe_line_id)) == ["il_3"]
    end

    test "follows the pagination of invoices and of lines" do
      page_1 = [invoice(id: "in_1", lines: lines([line(id: "il_1")], true))]
      # Stripe can hand back an id it already returned while it is being written to.
      page_2 = [invoice(id: "in_1"), invoice(id: "in_2")]

      list_invoices = fn params ->
        case Map.get(params, :starting_after) do
          nil -> {:ok, %{data: page_1, has_more: true}}
          "in_1" -> {:ok, %{data: page_2, has_more: false}}
        end
      end

      list_lines = fn "in_1", %{starting_after: "il_1"} ->
        {:ok, %{data: [line(id: "il_2")], has_more: false}}
      end

      {:ok, summary} =
        with_mock Sanbase.StripeApi, [:passthrough],
          list_invoices: list_invoices,
          list_invoice_line_items: list_lines do
          Sync.sync_range(Date.add(@today, -1), @today)
        end

      assert summary.invoices_upserted == 2
      assert Repo.aggregate(Invoice, :count) == 2

      [in_1] = Repo.all(from(i in Invoice, where: i.stripe_invoice_id == "in_1"))

      assert Repo.all(
               from(l in InvoiceLine,
                 where: l.invoice_id == ^in_1.id,
                 select: l.stripe_line_id,
                 order_by: l.stripe_line_id
               )
             ) == ["il_1", "il_2"]
    end

    test "records the run so the coverage is auditable" do
      admin = insert(:user)

      {:ok, _} =
        with_mocks [stripe_mock([invoice()])] do
          Sync.sync_range(Date.add(@today, -1), @today, triggered_by: admin.id)
        end

      assert [run] = InvoiceMirror.recent_runs()
      assert run.status == "completed"
      assert run.triggered_by == admin.id
      assert run.invoices_upserted == 1
      assert run.lines_upserted == 1
      assert is_integer(run.duration_ms)
      assert InvoiceMirror.last_synced_at() != nil
    end

    test "a Stripe error fails the run instead of importing part of the range" do
      with_mock Sanbase.StripeApi, [:passthrough],
        list_invoices: fn _params ->
          {:error, %Stripe.Error{source: :stripe, code: :api_error, message: "stripe is down"}}
        end do
        assert {:error, message} = Sync.sync_range(Date.add(@today, -1), @today)
        assert message =~ "stripe is down"
      end

      assert [run] = SyncRun.recent()
      assert run.status == "failed"
      assert run.error_message =~ "stripe is down"
      assert Repo.aggregate(Invoice, :count) == 0
      assert InvoiceMirror.last_synced_at() == nil
    end
  end

  describe "sync_range/3 guards" do
    test "refuses a range that ends before it starts or spans more than 3 years" do
      assert {:error, message} = Sync.sync_range(@today, Date.add(@today, -1))
      assert message =~ "start date"

      assert {:error, message} = Sync.sync_range(~D[2020-01-01], ~D[2023-01-02])
      assert message =~ "3 years"

      assert SyncRun.recent() == []
    end

    test "records nothing while another import holds the lock" do
      {namespace, key} = Sync.lock_keys()

      # Another node's import, on a connection of its own outside the test sandbox.
      config = Keyword.drop(Repo.config(), [:pool, :pool_size, :ownership_timeout])
      conn = start_supervised!({Postgrex, config})
      Postgrex.query!(conn, "SELECT pg_advisory_lock($1, $2)", [namespace, key])

      assert {:error, :already_running} = sync([invoice()])
      assert SyncRun.recent() == []
      assert Repo.aggregate(Invoice, :count) == 0

      Postgrex.query!(conn, "SELECT pg_advisory_unlock($1, $2)", [namespace, key])

      assert {:ok, %{invoices_upserted: 1}} = sync([invoice()])
    end

    test "marks runs left running for hours as interrupted" do
      {:ok, stale} = SyncRun.create(%{from_date: @today, to_date: @today, status: "running"})
      {:ok, recent} = SyncRun.create(%{from_date: @today, to_date: @today, status: "running"})

      seven_hours_ago =
        DateTime.utc_now() |> DateTime.add(-7, :hour) |> DateTime.truncate(:second)

      Repo.update_all(from(r in SyncRun, where: r.id == ^stale.id),
        set: [inserted_at: seven_hours_ago]
      )

      {:ok, _} = sync([invoice()])

      assert %{status: "failed", error_message: "interrupted"} = Repo.get!(SyncRun, stale.id)
      assert %{status: "running"} = Repo.get!(SyncRun, recent.id)
    end
  end

  describe "run/1" do
    test "fetches again the older open and uncollectible invoices" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for {id, status, days_ago} <- [
            {"in_open", "open", 30},
            {"in_uncollectible", "uncollectible", 60},
            {"in_ancient", "open", 500},
            {"in_paid", "paid", 30}
          ] do
        Repo.insert!(%Invoice{
          stripe_invoice_id: id,
          status: status,
          invoiced_at: DateTime.add(now, -days_ago, :day),
          synced_at: now
        })
      end

      created = DateTime.add(now, -30, :day) |> DateTime.to_unix()

      retrieve = fn
        "in_open" ->
          {:ok, invoice(id: "in_open", status: "paid", created: created, paid_out_of_band: true)}

        "in_uncollectible" ->
          {:ok, invoice(id: "in_uncollectible", status: "void", created: created)}
      end

      {:ok, summary} =
        with_mock Sanbase.StripeApi, [:passthrough],
          list_invoices: fn _params -> {:ok, %{data: [], has_more: false}} end,
          retrieve_invoice: retrieve do
          Sync.run()
        end

      assert summary.refresh == %{invoices_upserted: 2, lines_upserted: 2}

      statuses =
        Repo.all(from(i in Invoice, select: {i.stripe_invoice_id, i.status})) |> Map.new()

      assert statuses == %{
               "in_open" => "paid",
               "in_uncollectible" => "void",
               "in_ancient" => "open",
               "in_paid" => "paid"
             }

      assert %{paid_out_of_band: true} = Repo.get_by!(Invoice, stripe_invoice_id: "in_open")
    end
  end

  describe "plan backfill" do
    test "a line written before its plan had a Stripe id gets the plan on the next run",
         context do
      plan = context.plans.plan_business_pro_monthly

      {:ok, _} = sync([invoice(lines: lines([line(price: "price_added_later")]))])
      assert [%{plan_id: nil}] = Repo.all(InvoiceLine)

      Repo.update_all(from(p in Plan, where: p.id == ^plan.id),
        set: [stripe_id: "price_added_later"]
      )

      {:ok, _} = sync([invoice(id: "in_other", lines: lines([line(id: "il_other")]))])

      assert %{plan_id: plan_id} = Repo.get_by!(InvoiceLine, stripe_line_id: "il_1")
      assert plan_id == plan.id
    end
  end

  describe "InvoiceMirror.coverage/2" do
    test "reports only the days no completed run covers" do
      {:ok, _} = completed_run(~D[2026-01-01], ~D[2026-01-10])
      {:ok, _} = completed_run(~D[2026-01-20], ~D[2026-01-31])

      {:ok, _} =
        SyncRun.create(%{from_date: ~D[2026-01-11], to_date: ~D[2026-01-15], status: "failed"})

      assert InvoiceMirror.coverage(~D[2026-01-01], ~D[2026-01-31]) == [
               {~D[2026-01-11], ~D[2026-01-19]}
             ]
    end

    test "a run covers its range only up to the day before it started" do
      today = Date.utc_today()
      {:ok, _} = completed_run(Date.add(today, -3), today)

      assert InvoiceMirror.coverage(Date.add(today, -3), today) == [{today, today}]
      assert InvoiceMirror.coverage(Date.add(today, -3), Date.add(today, -1)) == []
    end
  end

  describe "SyncJob" do
    test "imports the range and broadcasts the result" do
      # Started by the admin application, which also runs in the test environment.
      assert is_pid(Process.whereis(SyncJob))
      SyncJob.subscribe()

      with_mocks [stripe_mock([invoice()])] do
        assert :ok = SyncJob.start_job(Date.add(@today, -1), @today, nil)
        assert_receive {:sync_update, %{status: :done, result: result}}, 5_000
        assert result.invoices_upserted == 1
      end

      assert %{status: :done} = SyncJob.get_state()
    end
  end

  # ─── Helpers ─────────────────────────────────────────────────────────────

  defp sync(invoices) do
    with_mocks [stripe_mock(invoices)] do
      Sync.sync_range(Date.add(@today, -1), @today)
    end
  end

  defp completed_run(from_date, to_date) do
    SyncRun.create(%{from_date: from_date, to_date: to_date, status: "completed"})
  end

  defp stripe_mock(invoices) do
    {Sanbase.StripeApi, [:passthrough],
     list_invoices: fn _params -> {:ok, %{data: invoices, has_more: false}} end}
  end

  defp invoice(overrides) do
    Map.merge(
      %{
        id: "in_test",
        number: "SAN-0001",
        customer: "cus_test",
        customer_email: "someone@example.com",
        subscription: "sub_test",
        created: DateTime.utc_now() |> DateTime.to_unix(),
        status: "paid",
        billing_reason: "subscription_cycle",
        currency: "usd",
        total: 12_000,
        total_excluding_tax: 10_000,
        tax: 2_000,
        amount_paid: 12_000,
        starting_balance: 0,
        ending_balance: 0,
        paid_out_of_band: false,
        status_transitions: %{paid_at: nil},
        lines: lines([line()])
      },
      Map.new(overrides)
    )
  end

  defp invoice, do: invoice([])

  defp lines(data, has_more \\ false), do: %{data: data, has_more: has_more}

  defp line(overrides \\ []) do
    now = DateTime.utc_now() |> DateTime.to_unix()

    Map.merge(
      %{
        id: "il_1",
        price: "price_test",
        plan: nil,
        description: "1 x PRO",
        period: %{start: now, end: now + 30 * 86_400},
        amount: 10_000,
        amount_excluding_tax: 10_000,
        quantity: 1,
        proration: false
      },
      Map.new(overrides)
    )
  end
end
