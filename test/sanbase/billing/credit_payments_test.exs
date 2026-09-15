defmodule Sanbase.Billing.CreditPaymentsTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory

  alias Sanbase.Billing.CreditPayments
  alias Sanbase.Billing.Subscription.SanBurnCreditTransaction

  @in_period DateTime.utc_now() |> DateTime.to_unix()

  describe "period_report/2 invoices" do
    test "an invoice paid from credit is reported with the credit it consumed" do
      report = report([invoice(starting_balance: -10_000, ending_balance: -4_000, total: 6_000)])

      assert [row] = report.invoices
      assert row.credit_applied == 6_000
      assert report.totals.credit_applied == 6_000
      assert report.totals.invoice_count == 1
    end

    test "an invoice paid by card only is not reported" do
      report =
        report([
          invoice(starting_balance: 0, ending_balance: 0, total: 6_000, amount_paid: 6_000)
        ])

      assert report.invoices == []
      assert report.totals.credit_applied == 0
    end

    test "an invoice that only carried the customer's debt forward is not reported" do
      report = report([invoice(starting_balance: 1_000, ending_balance: 0, total: 6_000)])

      assert report.invoices == []
    end

    test "an invoice marked paid out of band is reported even with no credit applied" do
      report =
        report([
          invoice(
            starting_balance: 0,
            ending_balance: 0,
            total: 6_000,
            paid_out_of_band: true
          )
        ])

      assert [row] = report.invoices
      assert row.paid_out_of_band
      assert report.totals.out_of_band_count == 1
    end

    test "an unpaid invoice is not reported" do
      report =
        report([
          invoice(starting_balance: -10_000, ending_balance: -4_000, total: 6_000, status: "open")
        ])

      assert report.invoices == []
    end

    test "the invoice is joined to the local user by stripe customer id" do
      user = insert(:user, stripe_customer_id: "cus_test")

      report = report([invoice(starting_balance: -10_000, ending_balance: -4_000, total: 6_000)])

      assert [row] = report.invoices
      assert row.user_id == user.id
      assert row.email == user.email
    end
  end

  describe "period_report/2 grants" do
    test "a credit adjustment is reported as money in, with its internal note" do
      note = "paid in crypto: https://etherscan.io/tx/0x" <> String.duplicate("a", 64)

      report =
        report(
          [invoice(starting_balance: -10_000, ending_balance: -4_000, total: 6_000)],
          [balance_transaction(amount: -10_000, description: note)]
        )

      assert [grant] = report.grants
      assert grant.amount == 10_000
      assert grant.description == note
      assert grant.source == :crypto
      assert report.totals.credit_granted == 10_000
      assert report.totals.by_source == %{crypto: 10_000}
    end

    test "credit applied to an invoice is not counted as money in" do
      report =
        report(
          [invoice(starting_balance: -10_000, ending_balance: -4_000, total: 6_000)],
          [balance_transaction(amount: 6_000, type: "applied_to_invoice", description: nil)]
        )

      assert report.grants == []
      assert report.totals.credit_granted == 0
    end

    test "a customer with no balance movement on any invoice is not scanned" do
      report =
        report(
          [invoice(starting_balance: 0, ending_balance: 0, total: 6_000, amount_paid: 6_000)],
          [balance_transaction(amount: -10_000, description: "wire transfer")]
        )

      assert report.grants == []
      assert report.scanned_customers == 0
    end

    test "an adjustment outside the period is not reported" do
      report =
        report(
          [invoice(starting_balance: -10_000, ending_balance: -4_000, total: 6_000)],
          [balance_transaction(amount: -10_000, created: 1)]
        )

      assert report.grants == []
    end
  end

  describe "period_report/2 source notes" do
    test "the invoice carries the note of the credit that funded it" do
      note = "https://etherscan.io/tx/0xfeed"

      report =
        report(
          [invoice(starting_balance: -10_000, ending_balance: -4_000, total: 6_000)],
          [
            balance_transaction(
              id: "cbtxn_grant",
              amount: -10_000,
              description: note,
              created: @in_period - 3600
            ),
            balance_transaction(
              id: "cbtxn_applied",
              amount: 6_000,
              type: "applied_to_invoice",
              description: nil,
              invoice: "in_test"
            )
          ]
        )

      assert [row] = report.invoices
      assert row.source_note == note
      assert row.source == :crypto
      assert row.funding_transaction_id == "cbtxn_grant"
      assert report.totals.credit_applied_by_source == %{crypto: 6_000}
    end

    test "the latest credit added before the invoice drew on the balance wins" do
      report =
        report(
          [invoice(starting_balance: -10_000, ending_balance: -4_000, total: 6_000)],
          [
            balance_transaction(
              id: "cbtxn_old",
              amount: -5_000,
              description: "old wire",
              created: @in_period - 100_000
            ),
            balance_transaction(
              id: "cbtxn_new",
              amount: -5_000,
              description: "recent wire",
              created: @in_period - 100
            )
          ]
        )

      assert [row] = report.invoices
      assert row.source_note == "recent wire"
    end

    test "credit added only after the invoice was opened is still matched to it" do
      report =
        report(
          [invoice(starting_balance: -10_000, ending_balance: -4_000, total: 6_000)],
          [
            balance_transaction(
              id: "cbtxn_late",
              amount: -10_000,
              description: "paid in crypto",
              created: @in_period + 1000
            )
          ]
        )

      assert [row] = report.invoices
      assert row.source_note == "paid in crypto"
    end

    test "an invoice with no adjustment on the ledger is reported without a note" do
      report = report([invoice(starting_balance: -10_000, ending_balance: -4_000, total: 6_000)])

      assert [row] = report.invoices
      assert row.source_note == nil
      assert row.source == :unknown
      assert report.totals.unmatched_note_count == 1
    end
  end

  describe "range_report/2" do
    test "spans every month between the two dates" do
      today = Date.utc_today()
      from = Date.add(today, -120)

      invoices = [invoice(starting_balance: -10_000, ending_balance: -4_000, total: 6_000)]

      report =
        with_mocks [
          {Sanbase.StripeApi, [:passthrough],
           list_invoices: fn params ->
             send(self(), {:params, params})
             {:ok, stripe_list(invoices)}
           end,
           list_customer_balance_transactions: fn _customer, _params ->
             {:ok, stripe_list([])}
           end}
        ] do
          CreditPayments.range_report(from, today)
        end

      assert [_row] = report.invoices
      assert_received {:params, %{created: %{gte: gte, lte: lte}}}
      assert gte < DateTime.to_unix(DateTime.new!(from, ~T[12:00:00]))
      assert lte > DateTime.to_unix(DateTime.new!(today, ~T[12:00:00]))
    end
  end

  describe "period_report/2 out of band" do
    test "the invoice memo is the note when no credit adjustment funded the invoice" do
      report =
        report([
          invoice(
            starting_balance: 0,
            ending_balance: 0,
            total: 600_000,
            paid_out_of_band: true,
            description: "Paid by wire transfer, ref QUBE-2026-05"
          )
        ])

      assert [row] = report.invoices
      assert row.source_note == "Paid by wire transfer, ref QUBE-2026-05"
      assert row.source == :wire
    end

    test "the credit adjustment still wins over the memo when there is one" do
      report =
        report(
          [
            invoice(
              starting_balance: -10_000,
              ending_balance: -4_000,
              total: 6_000,
              description: "some memo"
            )
          ],
          [balance_transaction(amount: -10_000, description: "https://etherscan.io/tx/0xabc")]
        )

      assert [row] = report.invoices
      assert row.source_note == "https://etherscan.io/tx/0xabc"
    end

    test "what an out of band invoice collected is totalled, not only counted" do
      report =
        report([
          invoice(
            id: "in_1",
            starting_balance: 0,
            ending_balance: 0,
            total: 600_000,
            paid_out_of_band: true
          ),
          invoice(
            id: "in_2",
            starting_balance: 0,
            ending_balance: 0,
            total: 270_000,
            paid_out_of_band: true
          )
        ])

      assert report.totals.out_of_band_count == 2
      assert report.totals.out_of_band_total == 870_000
      # Neither money column sees it, which is exactly why the total is needed.
      assert report.totals.credit_applied == 0
      assert report.totals.card_paid == 0
    end
  end

  describe "aggregate/2" do
    test "buckets the invoices by day, month, year or not at all" do
      rows = [
        row(created: ~U[2026-05-14 10:00:00Z], credit_applied: 24_900, total: 24_900),
        row(created: ~U[2026-05-26 10:00:00Z], credit_applied: 24_900, total: 24_900),
        row(created: ~U[2026-06-02 10:00:00Z], credit_applied: 48_000, total: 48_000)
      ]

      assert [%{label: "2026-06-02"}, %{label: "2026-05-26"}, %{label: "2026-05-14"}] =
               CreditPayments.aggregate(rows, :day)

      assert [
               %{label: "2026-06", credit_applied: 48_000, invoice_count: 1},
               %{label: "2026-05", credit_applied: 49_800, invoice_count: 2}
             ] = CreditPayments.aggregate(rows, :month)

      assert [%{label: "2026", credit_applied: 97_800, invoice_count: 3}] =
               CreditPayments.aggregate(rows, :year)

      assert [%{label: "Whole range", credit_applied: 97_800}] =
               CreditPayments.aggregate(rows, :all)
    end

    test "each bucket carries what was settled out of band" do
      rows = [
        row(created: ~U[2026-05-18 10:00:00Z], total: 600_000, paid_out_of_band: true),
        row(created: ~U[2026-05-14 10:00:00Z], total: 24_900, credit_applied: 24_900)
      ]

      assert [bucket] = CreditPayments.aggregate(rows, :month)
      assert bucket.out_of_band == 600_000
      assert bucket.credit_applied == 24_900
    end

    test "each bucket is split by source" do
      rows = [
        row(created: ~U[2026-05-14 10:00:00Z], credit_applied: 24_900, source: :crypto),
        row(created: ~U[2026-05-20 10:00:00Z], credit_applied: 5_000, source: :wire)
      ]

      assert [%{by_source: by_source}] = CreditPayments.aggregate(rows, :month)
      assert by_source == %{crypto: 24_900, wire: 5_000}
    end
  end

  describe "filter_invoices/2" do
    setup do
      rows = [
        row(email: "ops@grull.space", source: :crypto, source_note: "etherscan"),
        row(
          email: "max@santiment.net",
          source: :wire,
          source_note: "wire ref 42",
          number: "SAN-9"
        )
      ]

      %{rows: rows}
    end

    test "narrows by source", %{rows: rows} do
      assert [row] = CreditPayments.filter_invoices(rows, source: :wire)
      assert row.email == "max@santiment.net"
    end

    test "keeps everything when the source is :all", %{rows: rows} do
      assert CreditPayments.filter_invoices(rows, source: :all) == rows
      assert CreditPayments.filter_invoices(rows) == rows
    end

    test "matches the query against email, invoice number and note", %{rows: rows} do
      assert [%{email: "ops@grull.space"}] = CreditPayments.filter_invoices(rows, query: "GRULL")
      assert [%{number: "SAN-9"}] = CreditPayments.filter_invoices(rows, query: "san-9")
      assert [%{source: :wire}] = CreditPayments.filter_invoices(rows, query: "ref 42")
      assert CreditPayments.filter_invoices(rows, query: "nothing") == []
    end
  end

  describe "parse_source/1 and parse_granularity/1" do
    test "fall back instead of raising on junk" do
      assert CreditPayments.parse_source("crypto") == :crypto
      assert CreditPayments.parse_source("nonsense") == :all
      assert CreditPayments.parse_source(nil) == :all

      assert CreditPayments.parse_granularity("day") == :day
      assert CreditPayments.parse_granularity("nonsense") == :month
    end
  end

  describe "stripe urls" do
    test "point at the invoice and at the customer holding the note" do
      assert CreditPayments.stripe_invoice_url("in_1") ==
               "https://dashboard.stripe.com/invoices/in_1"

      assert CreditPayments.stripe_customer_url("cus_1") ==
               "https://dashboard.stripe.com/customers/cus_1"
    end
  end

  describe "classify_source/2" do
    test "a note naming a hash we burned ourselves is a SAN burn, not a payment" do
      hash = "0x" <> String.duplicate("b", 64)
      user = insert(:user)

      {:ok, _} =
        SanBurnCreditTransaction.create(%{
          address: "0x1",
          trx_hash: hash,
          san_amount: 1.0,
          san_price: 1.0,
          credit_amount: 1.0,
          trx_datetime: DateTime.utc_now() |> DateTime.truncate(:second),
          user_id: user.id
        })

      report =
        report(
          [invoice(starting_balance: -10_000, ending_balance: -4_000, total: 6_000)],
          [balance_transaction(amount: -10_000, description: "https://etherscan.io/tx/#{hash}")]
        )

      assert [grant] = report.grants
      assert grant.source == :san_burn
    end

    test "a note that says it burned SAN is a burn even with no recorded hash" do
      hashes = MapSet.new()

      assert CreditPayments.classify_source(
               "Burned 19289 SAN for 2700 credits. https://etherscan.io/tx/0x203eeb",
               hashes
             ) == :san_burn
    end

    test "notes are classified by their wording" do
      hashes = MapSet.new()

      assert CreditPayments.classify_source("wire transfer from ACME", hashes) == :wire
      assert CreditPayments.classify_source("https://etherscan.io/tx/0xabc", hashes) == :crypto
      assert CreditPayments.classify_source("goodwill", hashes) == :other
      assert CreditPayments.classify_source(nil, hashes) == :other
    end
  end

  # ─── Helpers ─────────────────────────────────────────────────────────────

  defp report(invoices, balance_transactions \\ []) do
    now = DateTime.utc_now()

    with_mocks [
      {Sanbase.StripeApi, [:passthrough],
       list_invoices: fn _params -> {:ok, stripe_list(invoices)} end,
       list_customer_balance_transactions: fn _customer, _params ->
         {:ok, stripe_list(balance_transactions)}
       end}
    ] do
      CreditPayments.period_report(now.year, now.month)
    end
  end

  defp stripe_list(data), do: %{data: data, has_more: false}

  defp invoice(opts) do
    %{
      id: Keyword.get(opts, :id, "in_test"),
      number: "SAN-0001",
      customer: Keyword.get(opts, :customer, "cus_test"),
      created: Keyword.get(opts, :created, @in_period),
      status: Keyword.get(opts, :status, "paid"),
      description: Keyword.get(opts, :description, nil),
      total: Keyword.get(opts, :total, 0),
      amount_paid: Keyword.get(opts, :amount_paid, 0),
      starting_balance: Keyword.get(opts, :starting_balance, 0),
      ending_balance: Keyword.get(opts, :ending_balance, 0),
      paid_out_of_band: Keyword.get(opts, :paid_out_of_band, false),
      hosted_invoice_url: "https://stripe.test/invoice",
      invoice_pdf: "https://stripe.test/invoice.pdf"
    }
  end

  defp row(opts) do
    %{
      id: Keyword.get(opts, :id, "in_test"),
      number: Keyword.get(opts, :number, "SAN-0001"),
      customer: Keyword.get(opts, :customer, "cus_test"),
      user_id: nil,
      email: Keyword.get(opts, :email, "user@example.com"),
      created: Keyword.get(opts, :created, DateTime.utc_now()),
      status: "paid",
      total: Keyword.get(opts, :total, 0),
      amount_paid: Keyword.get(opts, :amount_paid, 0),
      credit_applied: Keyword.get(opts, :credit_applied, 0),
      paid_out_of_band: Keyword.get(opts, :paid_out_of_band, false),
      hosted_invoice_url: nil,
      invoice_pdf: nil,
      source_note: Keyword.get(opts, :source_note, nil),
      source: Keyword.get(opts, :source, :unknown),
      funding_transaction_id: nil
    }
  end

  defp balance_transaction(opts) do
    %{
      id: Keyword.get(opts, :id, "cbtxn_test"),
      customer: Keyword.get(opts, :customer, "cus_test"),
      created: Keyword.get(opts, :created, @in_period),
      amount: Keyword.get(opts, :amount, 0),
      type: Keyword.get(opts, :type, "adjustment"),
      description: Keyword.get(opts, :description, "manual credit"),
      invoice: Keyword.get(opts, :invoice, nil)
    }
  end
end
