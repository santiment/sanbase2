defmodule SanbaseWeb.Admin.BusinessClientLiveTest do
  use SanbaseWeb.ConnCase, async: false

  @moduletag capture_log: true

  @async_timeout 5_000

  import Mock
  import Phoenix.LiveViewTest
  import Sanbase.Factory

  alias Sanbase.Accounts.UserRole
  alias Sanbase.Billing.BusinessClients
  alias Sanbase.Billing.BusinessClients.{ClientUsage, LogEntry, Report}
  alias Sanbase.Repo

  defp sign_in(role_factory) do
    user = insert(:user, email: "admin#{System.unique_integer([:positive])}@santiment.net")
    role = insert(role_factory)
    {:ok, _user_role} = UserRole.create(user.id, role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)

    {user, Plug.Test.init_test_session(build_conn(), jwt_tokens)}
  end

  defp client_for(user, attrs) do
    Map.merge(
      %{
        user_id: user.id,
        email: user.email,
        username: user.username,
        stripe_customer_id: "cus_detail",
        plan_name: "PRO",
        product_id: 2,
        interval: "year",
        business_reason: :business_email,
        mrr: 2_500,
        acv: 30_000,
        tcv: 60_000,
        start_date: ~D[2024-03-01],
        renewal_date: Date.add(Date.utc_today(), 90),
        paid_by: %{
          card: 30_000,
          wire: 0,
          crypto: 30_000,
          san_burn: 0,
          stripe_credit: 0,
          other: 0,
          unknown: 0,
          out_of_band: 0
        },
        subscription_status: "active",
        failed_payment?: true,
        unpaid_invoice?: false,
        api_calls: 300,
        api_calls_prev: 450,
        active_days: 4,
        active_days_prev: 12,
        risk_level: :high_risk,
        risk_reasons: ["Active on 4 of the last 30 days"],
        plan_limit: nil,
        upsell?: false,
        last_active_at: ~U[2026-10-19 12:00:00Z],
        last_web_active_at: ~U[2026-10-10 09:00:00Z],
        last_api_call_at: ~U[2026-10-19 12:00:00Z],
        manual_status: :healthy,
        open_entries_count: 0,
        retention_action?: false,
        override: nil
      },
      Map.new(attrs)
    )
  end

  defp detail_mock(user, client_attrs \\ %{}, opts \\ []) do
    client = if Keyword.get(opts, :client?, true), do: client_for(user, client_attrs)

    {Report, [:passthrough],
     [
       client_detail: fn _user_id ->
         %{
           client: client,
           user: %{id: user.id, email: user.email, username: user.username},
           invoices: [
             %{
               stripe_invoice_id: "in_detail_1",
               invoice_number: "SAN-1001",
               invoiced_at: ~U[2026-03-01 10:00:00Z],
               status: "paid",
               total_excluding_tax: 30_000,
               amount_paid: 0,
               credit_applied: 30_000,
               paid_out_of_band: false,
               source: :crypto,
               lines: [
                 %{
                   plan_name: "PRO",
                   period_start: ~D[2026-03-01],
                   period_end: ~D[2027-03-01],
                   amount_excluding_tax: 30_000,
                   discount: 0,
                   net_amount: 30_000,
                   proration: false
                 }
               ]
             }
           ],
           entries: [],
           override: nil
         }
       end,
       formula_notes: fn _settings -> %{acv: "ACV formula", tcv: "TCV formula"} end
     ]}
  end

  defp usage_mock(api, web, creations) do
    {ClientUsage, [:passthrough],
     [
       api: fn _user_id, _today -> api end,
       web: fn _user_id, _today -> web end,
       creations: fn _user_id, _today -> creations end
     ]}
  end

  @api {:ok,
        %{
          calls: %{current: 600, previous: 4_000},
          errors: 0,
          queries: [
            %{name: "getMetric|mvrv_usd", current: 600, previous: 1_600, errors: 0},
            %{name: "getMetric|exchange_inflow", current: 0, previous: 2_400, errors: 0}
          ],
          assets: [%{slug: "bitcoin", current: 600, previous: 4_000}],
          connections: [%{label: "Python", calls: 600, share: 1.0}]
        }}

  @web {:ok,
        %{
          areas: [%{area: "Charts", current: 12, previous: 30}],
          sql_runs: %{current: 3, previous: 0}
        }}

  @creations {:ok,
              [
                %{
                  kind: :watchlists,
                  label: "Watchlists",
                  total: 2,
                  active: nil,
                  changed_recently: 1,
                  last_changed_at: ~N[2026-11-01 10:00:00],
                  last_fired_at: nil
                },
                %{
                  kind: :alerts,
                  label: "Alerts",
                  total: 5,
                  active: 3,
                  changed_recently: 0,
                  last_changed_at: ~N[2026-09-01 10:00:00],
                  last_fired_at: ~U[2026-11-20 08:00:00Z]
                }
              ]}

  defp open_page(conn, user) do
    {:ok, view, _html} = live(conn, "/admin/business_clients/#{user.id}")
    render_async(view, @async_timeout)
    view
  end

  test "shows the client's numbers, invoices and lines" do
    {_admin, conn} = sign_in(:role_admin_panel_viewer)
    user = insert(:user, email: "boss@acme.com")

    with_mocks [detail_mock(user)] do
      view = open_page(conn, user)

      assert has_element?(view, "#client-title", "boss@acme.com")
      assert has_element?(view, "#client-summary", "$300")
      assert has_element?(view, "#client-summary", "$600")
      assert has_element?(view, "#client-summary", "Business email")
      assert has_element?(view, "#failed-payment")
      refute has_element?(view, "#unpaid-invoice")
      assert has_element?(view, ~s(#client-summary a[title="ACV formula"]))

      assert has_element?(
               view,
               ~s(a#stripe-customer[href="https://dashboard.stripe.com/customers/cus_detail"][target="_blank"][rel="noopener noreferrer"]),
               "cus_detail"
             )

      assert has_element?(view, "#last-active", "2026-10-19 12:00")
      assert has_element?(view, "#last-active .badge", "API")
      assert has_element?(view, "#last-active", "web: 2026-10-10 09:00")

      assert has_element?(
               view,
               ~s(#invoice-in_detail_1 a[href="https://dashboard.stripe.com/invoices/in_detail_1"]),
               "SAN-1001"
             )

      assert has_element?(view, "#invoice-in_detail_1", "$300.00")
      assert has_element?(view, "#invoice-in_detail_1", "Crypto")
      assert has_element?(view, "#invoice-in_detail_1", "2026-03-01 - 2027-03-01")
    end
  end

  test "shows what the client does with the product, with a brief for the call" do
    {_admin, conn} = sign_in(:role_admin_panel_viewer)
    user = insert(:user, email: "boss@acme.com")

    plan_limit = %{
      limit: 600_000,
      months:
        for(
          i <- 6..1//-1,
          do: %{month: Date.shift(~D[2026-11-01], month: -i), calls: 0, share: 0.0}
        ),
      last_month: %{month: ~D[2026-10-01], calls: 0, share: 0.0},
      pace: %{calls: 1_000, share: 0.0017, partial?: false},
      months_at_high: 0,
      upsell?: false,
      upsell_reason: nil
    }

    with_mocks [
      detail_mock(user, %{plan_limit: plan_limit}),
      usage_mock(@api, @web, @creations)
    ] do
      view = open_page(conn, user)

      # The brief: a client at risk gets it highlighted.
      assert has_element?(view, "#usage-brief.border-warning")
      assert has_element?(view, "#usage-brief", "Active on 4 of the last 30 days, was 12.")
      assert has_element?(view, "#usage-brief", "API calls down 85%")
      assert has_element?(view, "#usage-brief", "Stopped calling exchange_inflow")
      assert has_element?(view, "#usage-brief", "Has built 3 active alert(s), 2 watchlist(s).")
      refute has_element?(view, "#usage-partial")

      assert has_element?(view, "#plan-limit", "600,000 calls a month")
      refute has_element?(view, "#upsell-badge")

      assert has_element?(view, "#stopped-queries", "exchange_inflow")
      assert has_element?(view, "#api-queries", "mvrv_usd")
      assert has_element?(view, "#api-queries", "-63%")
      assert has_element?(view, "#api-assets", "bitcoin")
      assert has_element?(view, "#api-connections", "Python 100%")

      assert has_element?(view, "#web-areas", "Charts")
      assert has_element?(view, "#sql-runs", "3")
      assert has_element?(view, "#creation-alerts", "3 on, last fired 2026-11-20 08:00")
      assert has_element?(view, "#creation-watchlists", "2")
    end
  end

  test "a usage source that failed is said so, and the rest still shows" do
    {_admin, conn} = sign_in(:role_admin_panel_viewer)
    user = insert(:user, email: "boss@acme.com")

    with_mocks [detail_mock(user), usage_mock(:error, @web, @creations)] do
      view = open_page(conn, user)

      assert has_element?(view, "#usage-partial")
      assert has_element?(view, "#api-usage", "could not be read")
      assert has_element?(view, "#web-areas", "Charts")
      refute has_element?(view, "#plan-limit")
    end
  end

  test "an unpaid invoice is not a failed payment; no customer id, no Stripe link" do
    {_admin, conn} = sign_in(:role_admin_panel_viewer)
    user = insert(:user)

    attrs = %{failed_payment?: false, unpaid_invoice?: true, stripe_customer_id: nil}

    with_mocks [detail_mock(user, attrs)] do
      view = open_page(conn, user)

      assert has_element?(view, "#unpaid-invoice", "unpaid invoice")
      refute has_element?(view, "#failed-payment")
      refute has_element?(view, "#stripe-customer")
    end
  end

  test "highlights a renewal within 30 days only on a renewal interval" do
    {_admin, conn} = sign_in(:role_admin_panel_viewer)
    user = insert(:user)
    soon = Date.add(Date.utc_today(), 5)

    with_mocks [detail_mock(user, %{interval: "year", renewal_date: soon})] do
      view = open_page(conn, user)
      assert has_element?(view, "#renewal-date.text-warning")
      assert has_element?(view, "#renewal-soon")
    end

    with_mocks [detail_mock(user, %{interval: "month", renewal_date: soon})] do
      view = open_page(conn, user)
      assert has_element?(view, "#renewal-date", Date.to_iso8601(soon))
      refute has_element?(view, "#renewal-date.text-warning")
      refute has_element?(view, "#renewal-soon")
    end
  end

  test "the formula notes start collapsed and an asterisk opens them" do
    {_admin, conn} = sign_in(:role_admin_panel_viewer)
    user = insert(:user)

    with_mocks [detail_mock(user)] do
      view = open_page(conn, user)

      refute has_element?(view, "#formula-notes[open]")

      view |> element(~s(#client-summary a[href="#formula-acv"])) |> render_click()
      assert has_element?(view, "#formula-notes[open]")
      assert has_element?(view, "#formula-acv", "ACV formula")
    end
  end

  test "says so when the user is not a business client today" do
    {_admin, conn} = sign_in(:role_admin_panel_viewer)
    user = insert(:user)

    with_mocks [detail_mock(user, %{}, client?: false)] do
      view = open_page(conn, user)

      assert has_element?(view, "#not-a-client")
      refute has_element?(view, "#client-summary")
    end
  end

  describe "log entries" do
    test "an editor adds an entry and resolves it" do
      {admin, conn} = sign_in(:role_admin_panel_editor)
      user = insert(:user)

      with_mocks [detail_mock(user)] do
        view = open_page(conn, user)

        # The Log link of the client list lands here.
        assert has_element?(view, "#add-entry-panel #entry-form")
        assert has_element?(view, "#log-entries-empty")

        view
        |> form("#entry-form", %{
          "entry" => %{"type" => "Complaint", "severity" => "at_risk", "note" => "Data late"}
        })
        |> render_submit()

        [entry] = BusinessClients.list_entries(user.id)
        assert entry.type == "Complaint"
        assert entry.severity == "at_risk"
        assert entry.author_id == admin.id

        assert has_element?(view, "#entries-#{entry.id}", "Data late")
        assert has_element?(view, "#entries-#{entry.id}", "At Risk")

        view |> element("#resolve-entry-#{entry.id}") |> render_click()

        assert %LogEntry{resolved_at: %DateTime{}, resolved_by_id: resolved_by} =
                 Repo.get(LogEntry, entry.id)

        assert resolved_by == admin.id
        refute has_element?(view, "#resolve-entry-#{entry.id}")
        assert has_element?(view, "#entries-#{entry.id}", admin.email)
      end
    end

    test "a type without severity disables the severity and stores none" do
      {_admin, conn} = sign_in(:role_admin_panel_editor)
      user = insert(:user)

      with_mocks [detail_mock(user)] do
        view = open_page(conn, user)

        view
        |> form("#entry-form", %{"entry" => %{"type" => "Retention action"}})
        |> render_change()

        assert has_element?(view, "#entry_severity[disabled]")
        assert has_element?(view, "#severity-disabled-hint")

        view
        |> form("#entry-form", %{"entry" => %{"type" => "Retention action", "note" => "Call"}})
        |> render_submit()

        assert [%LogEntry{type: "Retention action", severity: "none"}] =
                 BusinessClients.list_entries(user.id)
      end
    end

    test "notes are rendered escaped" do
      {admin, conn} = sign_in(:role_admin_panel_viewer)
      user = insert(:user)

      {:ok, entry} =
        BusinessClients.create_entry(user.id, admin.id, %{
          "type" => "Complaint",
          "note" => "<script>alert(1)</script>"
        })

      with_mocks [detail_mock(user)] do
        view = open_page(conn, user)

        refute has_element?(view, "#entries-#{entry.id} script")
        assert render(view) =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
      end
    end

    test "a viewer cannot add or resolve entries" do
      {admin, conn} = sign_in(:role_admin_panel_viewer)
      user = insert(:user)

      {:ok, entry} =
        BusinessClients.create_entry(user.id, admin.id, %{
          "type" => "Complaint",
          "severity" => "high_risk"
        })

      with_mocks [detail_mock(user)] do
        view = open_page(conn, user)

        refute has_element?(view, "#entry-form")
        refute has_element?(view, "#resolve-entry-#{entry.id}")

        render_hook(view, "add_entry", %{"entry" => %{"type" => "Complaint", "note" => "x"}})
        assert render(view) =~ "needs the Admin Panel Editor role"

        render_hook(view, "resolve_entry", %{"id" => to_string(entry.id)})

        assert [%LogEntry{id: id, resolved_at: nil}] = BusinessClients.list_entries(user.id)
        assert id == entry.id
      end
    end

    test "an entry of another user cannot be resolved from this page" do
      {admin, conn} = sign_in(:role_admin_panel_editor)
      user = insert(:user)
      other = insert(:user)

      {:ok, other_entry} =
        BusinessClients.create_entry(other.id, admin.id, %{"type" => "Complaint"})

      with_mocks [detail_mock(user)] do
        view = open_page(conn, user)

        render_hook(view, "resolve_entry", %{"id" => to_string(other_entry.id)})
        assert is_nil(Repo.get(LogEntry, other_entry.id).resolved_at)
      end
    end
  end

  describe "override" do
    test "an editor sets and clears the business override" do
      {admin, conn} = sign_in(:role_admin_panel_editor)
      user = insert(:user)

      with_mocks [detail_mock(user)] do
        view = open_page(conn, user)

        assert has_element?(view, "#override-panel")

        view
        |> form("#override-form", %{
          "override" => %{"business" => "false", "note" => "Personal account"}
        })
        |> render_submit()

        assert BusinessClients.overrides() == %{user.id => false}
        assert has_element?(view, "#override-state", "not business")
        assert has_element?(view, "#override-state", "Personal account")
        assert has_element?(view, "#override-state", admin.email)

        view |> element("#clear-override") |> render_click()

        assert BusinessClients.overrides() == %{}
        assert has_element?(view, "#override-state", "No override")
      end
    end

    test "a business-plan client has no override control" do
      {_admin, conn} = sign_in(:role_admin_panel_editor)
      user = insert(:user)

      with_mocks [detail_mock(user, %{business_reason: :plan, plan_name: "BUSINESS_PRO"})] do
        view = open_page(conn, user)
        refute has_element?(view, "#override-panel")
      end
    end

    test "a viewer cannot change the override" do
      {_admin, conn} = sign_in(:role_admin_panel_viewer)
      user = insert(:user)

      with_mocks [detail_mock(user)] do
        view = open_page(conn, user)

        refute has_element?(view, "#override-form")

        render_hook(view, "set_override", %{"override" => %{"business" => "true"}})
        assert BusinessClients.overrides() == %{}
      end
    end
  end
end
