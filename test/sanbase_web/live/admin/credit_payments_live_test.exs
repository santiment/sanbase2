defmodule SanbaseWeb.Admin.CreditPaymentsLiveTest do
  use SanbaseWeb.ConnCase, async: false

  @moduletag capture_log: true

  import Mock
  import Phoenix.LiveViewTest
  import Sanbase.Factory

  setup do
    user = insert(:user)
    admin_role = insert(:role_admin_panel_viewer)
    {:ok, _user_role} = Sanbase.Accounts.UserRole.create(user.id, admin_role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)
    conn = Plug.Test.init_test_session(build_conn(), jwt_tokens)
    {:ok, conn: conn}
  end

  test "lists the invoices settled from credit and the notes behind them", %{conn: conn} do
    note = "paid in crypto: https://etherscan.io/tx/0xabc"

    seed([invoice(id: "in_test", number: "SAN-0001")], [adjustment(description: note)])

    {:ok, view, _html} = live(conn, "/admin/credit_payments")
    html = render_async(view)

    assert html =~ "Credit Payments"
    assert html =~ "SAN-0001"
    # $6,000.00 paid from credit, $10,000.00 credit added
    assert html =~ "$6,000.00"
    assert html =~ "$10,000.00"
    assert html =~ note
    assert html =~ "Crypto"
  end

  test "says so when nothing was settled from credit", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/credit_payments")
    html = render_async(view)

    assert html =~ "No invoice was settled from credit in this range."
    assert html =~ "No credit was added in this range."
  end

  test "warns about the days no import has covered", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/credit_payments")

    assert render_async(view) =~ "Never imported:"
  end

  test "re-imports the selected range from Stripe on demand", %{conn: conn} do
    invoices = [invoice(id: "in_late", number: "SAN-LATE")]
    transactions = [adjustment(description: "wire transfer ref 42")]

    with_mocks [stripe_mock(invoices, transactions)] do
      {:ok, view, _html} = live(conn, "/admin/credit_payments")
      html = render_async(view)

      refute html =~ "SAN-LATE"

      render_click(view, "resync", %{})

      # The job runs in a task and reports back over PubSub; wait for the page to
      # show the imported row.
      assert eventually(fn -> render(view) =~ "SAN-LATE" end)
      refute render(view) =~ "Never imported:"
    end
  end

  test "looks up one customer's full balance ledger by email", %{conn: conn} do
    user = insert(:user, stripe_customer_id: "cus_lookup")

    transaction =
      adjustment(
        id: "cbtxn_lookup",
        customer: "cus_lookup",
        amount: -50_000,
        description: "wire transfer, ref 12345"
      )

    with_mocks [stripe_mock([], [transaction])] do
      {:ok, view, _html} = live(conn, "/admin/credit_payments")
      render_async(view)

      html =
        view
        |> form("#lookup-form", %{"email" => user.email})
        |> render_submit()

      html = render_async(view) || html

      assert html =~ "wire transfer, ref 12345"
      assert html =~ "$500.00"
      assert html =~ "Wire / bank"
    end
  end

  test "reports a user without a stripe customer id instead of failing", %{conn: conn} do
    user = insert(:user, stripe_customer_id: nil)

    {:ok, view, _html} = live(conn, "/admin/credit_payments")
    render_async(view)

    view
    |> form("#lookup-form", %{"email" => user.email})
    |> render_submit()

    assert render_async(view) =~ "No user with a stripe customer id"
  end

  # The import runs in a supervised task, so the page catches up a moment later.
  defp eventually(fun, attempts \\ 50) do
    cond do
      fun.() -> true
      attempts <= 0 -> false
      true -> Process.sleep(20) && eventually(fun, attempts - 1)
    end
  end

  defp invoice(overrides) do
    Map.merge(
      %{
        id: "in_test",
        number: "SAN-0001",
        customer: "cus_test",
        created: DateTime.utc_now() |> DateTime.to_unix(),
        status: "paid",
        total: 600_000,
        amount_paid: 0,
        starting_balance: -1_000_000,
        ending_balance: -400_000,
        paid_out_of_band: false,
        hosted_invoice_url: "https://stripe.test/invoice",
        invoice_pdf: "https://stripe.test/invoice.pdf"
      },
      Map.new(overrides)
    )
  end

  defp adjustment(overrides) do
    Map.merge(
      %{
        id: "cbtxn_test",
        customer: "cus_test",
        created: DateTime.utc_now() |> DateTime.to_unix(),
        amount: -1_000_000,
        type: "adjustment",
        description: "manual credit",
        invoice: nil
      },
      Map.new(overrides)
    )
  end

  defp stripe_mock(invoices, transactions) do
    {Sanbase.StripeApi, [:passthrough],
     list_invoices: fn _params -> {:ok, %{data: invoices, has_more: false}} end,
     list_customer_balance_transactions: fn _customer, _params ->
       {:ok, %{data: transactions, has_more: false}}
     end}
  end

  # The page reads the local mirror, so a test has to import into it first - which is
  # also the cheapest way to exercise the importer itself.
  defp seed(invoices, transactions, opts \\ []) do
    today = Date.utc_today()
    from = Keyword.get(opts, :from, Date.add(today, -365))
    to = Keyword.get(opts, :to, today)

    with_mocks [stripe_mock(invoices, transactions)] do
      {:ok, _summary} = Sanbase.Billing.CreditPayments.Sync.sync_range(from, to)
    end
  end

  test "filters the invoices by source and by free text", %{conn: conn} do
    invoices = [
      invoice(id: "in_crypto", number: "SAN-CRYPTO", customer: "cus_a"),
      invoice(id: "in_wire", number: "SAN-WIRE", customer: "cus_b")
    ]

    transactions = [
      adjustment(id: "cbtxn_a", customer: "cus_a", description: "https://etherscan.io/tx/0xabc"),
      adjustment(id: "cbtxn_b", customer: "cus_b", description: "wire transfer ref 42")
    ]

    seed(invoices, transactions)

    {:ok, view, _html} = live(conn, "/admin/credit_payments")
    render_async(view)

    html =
      view
      |> form("#filter-form", %{"source" => "wire"})
      |> render_change()

    refute html =~ "SAN-CRYPTO"
    assert html =~ "SAN-WIRE"

    html =
      view
      |> form("#filter-form", %{"source" => "all", "query" => "etherscan"})
      |> render_change()

    assert html =~ "SAN-CRYPTO"
    refute html =~ "SAN-WIRE"
  end

  test "paginates the invoice table", %{conn: conn} do
    invoices =
      for index <- 1..30 do
        invoice(id: "in_#{index}", number: "SAN-#{index}", customer: "cus_#{index}")
      end

    seed(invoices, [])

    {:ok, view, _html} = live(conn, "/admin/credit_payments")
    html = render_async(view)

    assert html =~ "30 invoice(s), page 1 of 2"

    html = view |> element("button", "Next") |> render_click()

    assert html =~ "page 2 of 2"
  end

  test "aggregates the invoices by the chosen granularity", %{conn: conn} do
    day = ~U[2026-05-14 10:00:00Z] |> DateTime.to_unix()

    invoices = [
      invoice(id: "in_1", number: "SAN-1", created: day),
      invoice(id: "in_2", number: "SAN-2", created: day + 86_400)
    ]

    seed(invoices, [], from: ~D[2026-05-01], to: ~D[2026-05-31])

    {:ok, view, _html} = live(conn, "/admin/credit_payments")
    render_async(view)

    html =
      view
      |> form("#range-form", %{"from" => "2026-05-01", "to" => "2026-05-31"})
      |> render_change()

    html = render_async(view) || html
    assert html =~ "2026-05"

    html =
      view
      |> form("#filter-form", %{"granularity" => "day"})
      |> render_change()

    assert html =~ "2026-05-14"
    assert html =~ "2026-05-15"
  end

  test "offers a CSV download carrying the current range and filters", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/credit_payments")
    html = render_async(view)

    assert html =~ "/admin/credit_payments/export?"
    assert html =~ "what=invoices"
    assert html =~ "what=grants"
  end

  describe "CSV export" do
    test "returns the invoices settled from credit", %{conn: conn} do
      invoices = [invoice(id: "in_test", number: "SAN-0001")]
      transactions = [adjustment(description: "https://etherscan.io/tx/0xabc")]

      seed(invoices, transactions)

      conn =
        get(conn, ~p"/admin/credit_payments/export", %{
          "from" => "2026-01-01",
          "to" => "2026-12-31",
          "what" => "invoices"
        })

      assert response_content_type(conn, :csv)
      body = response(conn, 200)

      assert body =~ "number,invoice_id,customer_email"
      assert body =~ "SAN-0001"
      assert body =~ "6000.00"
      assert body =~ "https://dashboard.stripe.com/invoices/in_test"
      assert body =~ "https://etherscan.io/tx/0xabc"
    end

    test "returns the credit grants when asked for them", %{conn: conn} do
      invoices = [invoice(id: "in_test")]
      transactions = [adjustment(description: "wire transfer ref 42")]

      seed(invoices, transactions)

      conn =
        get(conn, ~p"/admin/credit_payments/export", %{
          "from" => "2026-01-01",
          "to" => "2026-12-31",
          "what" => "grants"
        })

      body = response(conn, 200)

      assert body =~ "date,customer_email"
      assert body =~ "wire transfer ref 42"
      assert body =~ "10000.00"
    end

    test "redirects instead of exporting when the range is invalid", %{conn: conn} do
      conn = get(conn, ~p"/admin/credit_payments/export", %{"from" => "nope", "to" => "nope"})

      assert redirected_to(conn) == "/admin/credit_payments"
    end
  end
end
