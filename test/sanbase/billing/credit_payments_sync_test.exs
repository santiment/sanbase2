defmodule Sanbase.Billing.CreditPaymentsSyncTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory

  alias Sanbase.Billing.CreditPayments.{CreditInvoice, Store, Sync, SyncRun}
  alias Sanbase.Repo

  @today Date.utc_today()

  describe "sync_range/3" do
    test "writes the credit-settled invoices and the ledger behind them" do
      user = insert(:user, stripe_customer_id: "cus_test")
      note = "https://etherscan.io/tx/0xabc"

      {:ok, summary} = sync([invoice()], [adjustment(description: note)])

      assert summary.invoices_upserted == 1
      assert summary.grants_upserted == 1
      assert summary.customers_scanned == 1

      assert [row] = Store.invoices(Date.add(@today, -1), @today)
      assert row.number == "SAN-0001"
      assert row.credit_applied == 6_000
      assert row.source == :crypto
      assert row.source_note == note
      assert row.user_id == user.id
      assert row.email == user.email
    end

    test "an invoice paid by card only is not mirrored" do
      {:ok, _summary} =
        sync([invoice(starting_balance: 0, ending_balance: 0, amount_paid: 6_000)], [])

      assert Store.invoices(Date.add(@today, -1), @today) == []
    end

    test "running it twice writes one row, not two" do
      {:ok, _} = sync([invoice()], [adjustment()])
      {:ok, _} = sync([invoice()], [adjustment()])

      assert Repo.aggregate(CreditInvoice, :count) == 1
    end

    test "a second run rewrites the classification of rows already imported" do
      {:ok, _} = sync([invoice()], [adjustment(description: "no idea")])

      assert [%{source: :other}] = Store.invoices(Date.add(@today, -1), @today)

      {:ok, _} = sync([invoice()], [adjustment(description: "wire transfer ref 42")])

      assert [row] = Store.invoices(Date.add(@today, -1), @today)
      assert row.source == :wire
      assert row.source_note == "wire transfer ref 42"
    end

    test "an invoice that stops qualifying is dropped on the next run" do
      {:ok, _} = sync([invoice()], [adjustment()])
      assert Repo.aggregate(CreditInvoice, :count) == 1

      {:ok, _} = sync([], [])
      assert Repo.aggregate(CreditInvoice, :count) == 0
    end

    test "records the run so the coverage is auditable" do
      admin = insert(:user)

      {:ok, _} =
        with_mocks [stripe_mock([invoice()], [adjustment()])] do
          Sync.sync_range(Date.add(@today, -1), @today, triggered_by: admin.id)
        end

      assert [run] = SyncRun.recent()
      assert run.status == "completed"
      assert run.triggered_by == admin.id
      assert run.invoices_upserted == 1
      assert is_integer(run.duration_ms)
    end

    test "a failure is recorded instead of being swallowed" do
      with_mock Sanbase.StripeApi, [:passthrough],
        list_invoices: fn _params -> raise "stripe is down" end do
        assert {:error, message} = Sync.sync_range(Date.add(@today, -1), @today)
        assert message =~ "stripe is down"
      end

      assert [run] = SyncRun.recent()
      assert run.status == "failed"
      assert run.error_message =~ "stripe is down"
    end
  end

  describe "SyncRun.gaps/2" do
    test "reports the whole range when nothing has been imported" do
      assert SyncRun.gaps(~D[2026-01-01], ~D[2026-01-05]) == [{~D[2026-01-01], ~D[2026-01-05]}]
    end

    test "reports nothing when a completed run covers the range" do
      {:ok, _} = completed_run(~D[2026-01-01], ~D[2026-01-31])

      assert SyncRun.gaps(~D[2026-01-05], ~D[2026-01-10]) == []
    end

    test "reports only the days no run covers, grouped into ranges" do
      {:ok, _} = completed_run(~D[2026-01-01], ~D[2026-01-10])
      {:ok, _} = completed_run(~D[2026-01-20], ~D[2026-01-31])

      assert SyncRun.gaps(~D[2026-01-01], ~D[2026-01-31]) == [{~D[2026-01-11], ~D[2026-01-19]}]
    end

    test "a failed run does not count as coverage" do
      {:ok, _} =
        SyncRun.create(%{from_date: ~D[2026-01-01], to_date: ~D[2026-01-31], status: "failed"})

      assert SyncRun.gaps(~D[2026-01-01], ~D[2026-01-31]) == [{~D[2026-01-01], ~D[2026-01-31]}]
    end
  end

  describe "Store.range_report/2" do
    test "totals the mirror the same way the live report totals Stripe" do
      {:ok, _} =
        sync(
          [invoice(), invoice(id: "in_2", number: "SAN-0002", customer: "cus_2")],
          [adjustment(description: "wire transfer ref 42")]
        )

      report = Store.range_report(Date.add(@today, -1), @today)

      assert report.totals.invoice_count == 2
      assert report.totals.credit_applied == 12_000
      assert report.totals.credit_granted == 10_000
      assert report.totals.by_source == %{wire: 10_000}
      assert report.last_synced_at != nil
      assert report.coverage == []
    end

    test "the customer ledger comes back with every entry, not only the credits" do
      {:ok, _} =
        sync([invoice()], [
          adjustment(description: "wire transfer ref 42"),
          adjustment(
            id: "cbtxn_applied",
            amount: 6_000,
            type: "applied_to_invoice",
            description: nil,
            invoice: "in_test"
          )
        ])

      assert [_, _] = ledger = Store.customer_ledger("cus_test")
      assert Enum.any?(ledger, &(&1.type == "applied_to_invoice"))
      # Stripe's sign is kept in the mirror and flipped for display.
      assert Enum.any?(ledger, &(&1.amount == 10_000))
    end
  end

  # ─── Helpers ─────────────────────────────────────────────────────────────

  defp sync(invoices, transactions) do
    with_mocks [stripe_mock(invoices, transactions)] do
      Sync.sync_range(Date.add(@today, -1), @today)
    end
  end

  defp completed_run(from_date, to_date) do
    SyncRun.create(%{from_date: from_date, to_date: to_date, status: "completed"})
  end

  defp stripe_mock(invoices, transactions) do
    {Sanbase.StripeApi, [:passthrough],
     list_invoices: fn _params -> {:ok, %{data: invoices, has_more: false}} end,
     list_customer_balance_transactions: fn _customer, _params ->
       {:ok, %{data: transactions, has_more: false}}
     end}
  end

  defp invoice(overrides \\ []) do
    Map.merge(
      %{
        id: "in_test",
        number: "SAN-0001",
        customer: "cus_test",
        created: DateTime.utc_now() |> DateTime.to_unix(),
        status: "paid",
        total: 6_000,
        amount_paid: 0,
        starting_balance: -10_000,
        ending_balance: -4_000,
        paid_out_of_band: false,
        hosted_invoice_url: "https://stripe.test/invoice",
        invoice_pdf: "https://stripe.test/invoice.pdf"
      },
      Map.new(overrides)
    )
  end

  defp adjustment(overrides \\ []) do
    Map.merge(
      %{
        id: "cbtxn_test",
        customer: "cus_test",
        created: DateTime.utc_now() |> DateTime.to_unix(),
        amount: -10_000,
        type: "adjustment",
        description: "manual credit",
        invoice: nil
      },
      Map.new(overrides)
    )
  end
end
