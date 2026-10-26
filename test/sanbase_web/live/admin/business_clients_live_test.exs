defmodule SanbaseWeb.Admin.BusinessClientsLiveTest do
  use SanbaseWeb.ConnCase, async: false

  @moduletag capture_log: true

  @async_timeout 5_000

  import Mock
  import Phoenix.LiveViewTest
  import Sanbase.Factory

  alias Sanbase.Accounts.UserRole
  alias Sanbase.Billing.BusinessClients
  alias Sanbase.Billing.BusinessClients.{Report, Settings}
  alias Sanbase.Billing.InvoiceMirror
  alias Sanbase.Billing.InvoiceMirror.SyncJob

  defp sign_in(role_factory) do
    user = insert(:user, email: "admin#{System.unique_integer([:positive])}@santiment.net")
    role = insert(role_factory)
    {:ok, _user_role} = UserRole.create(user.id, role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)

    {user, Plug.Test.init_test_session(build_conn(), jwt_tokens)}
  end

  defp client(attrs) do
    Map.merge(
      %{
        user_id: 1,
        email: "client@acme.com",
        username: "acme",
        stripe_customer_id: "cus_acme",
        plan_name: "BUSINESS_PRO",
        product_id: 2,
        interval: "year",
        business_reason: :plan,
        mrr: 42_000,
        acv: 504_000,
        tcv: 1_008_000,
        start_date: ~D[2024-01-15],
        renewal_date: Date.add(today(), 200),
        paid_by: %{
          card: 504_000,
          wire: 504_000,
          crypto: 0,
          san_burn: 0,
          stripe_credit: 0,
          other: 0,
          unknown: 0,
          out_of_band: 0
        },
        subscription_status: "active",
        failed_payment?: false,
        unpaid_invoice?: false,
        api_calls: 1_200,
        api_calls_prev: 900,
        last_active_at: ~U[2026-10-20 10:00:00Z],
        last_web_active_at: ~U[2026-10-20 10:00:00Z],
        last_api_call_at: nil,
        manual_status: :healthy,
        open_entries_count: 0,
        retention_action?: false,
        override: nil
      },
      Map.new(attrs)
    )
  end

  defp metrics(attrs \\ %{}) do
    Map.merge(
      %{
        as_of: today(),
        window: %{from: Date.add(today(), -365), to: today()},
        client_count: 3,
        mrr: 100_000,
        at_risk_count: 1,
        retention_action_pct: 50.0,
        client_churn: %{rate: 0.25, lost: 1, base: 4},
        revenue_churn: %{rate: 0.1, lost_mrr: 10_000, base_mrr: 100_000, expansion_mrr: 5_000},
        client_renewal: %{rate: 0.75, renewed: 3, due: 4},
        revenue_renewal: %{rate: 0.8, renewed_acv: 800_000, due_acv: 1_000_000},
        segments: %{
          plan: %{
            client_count: 2,
            mrr: 60_000,
            at_risk_count: 0,
            retention_action_pct: nil,
            client_churn: %{rate: 0.0, lost: 0, base: 1},
            revenue_churn: %{rate: 0.0, lost_mrr: 0, base_mrr: 60_000, expansion_mrr: 5_000},
            client_renewal: %{rate: 1.0, renewed: 2, due: 2},
            revenue_renewal: %{rate: 1.0, renewed_acv: 700_000, due_acv: 700_000}
          },
          business_email: %{
            client_count: 1,
            mrr: 40_000,
            at_risk_count: 1,
            retention_action_pct: 50.0,
            client_churn: %{rate: 1 / 3, lost: 1, base: 3},
            revenue_churn: %{rate: 0.25, lost_mrr: 10_000, base_mrr: 40_000, expansion_mrr: 0},
            client_renewal: %{rate: 0.5, renewed: 1, due: 2},
            revenue_renewal: %{rate: 1 / 3, renewed_acv: 100_000, due_acv: 300_000}
          }
        },
        settings: Settings.defaults()
      },
      Map.new(attrs)
    )
  end

  defp notes do
    Map.new(SanbaseWeb.Admin.BusinessClientsLive.note_keys(), &{&1, "Formula for #{&1}"})
  end

  defp clients do
    [
      client(
        user_id: 101,
        email: "big@acme.com",
        mrr: 90_000,
        acv: 1_080_000,
        last_active_at: ~U[2026-10-21 08:00:00Z],
        last_api_call_at: ~U[2026-10-21 08:00:00Z]
      ),
      client(
        user_id: 102,
        email: "risky@globex.com",
        username: "globex",
        plan_name: "PRO",
        business_reason: :business_email,
        mrr: 5_000,
        acv: 60_000,
        renewal_date: Date.add(today(), 10),
        manual_status: :at_risk,
        open_entries_count: 2,
        failed_payment?: true
      ),
      client(
        user_id: 103,
        email: "small@initech.com",
        plan_name: "MAX",
        business_reason: :override,
        override: true,
        mrr: 1_000,
        acv: 12_000,
        stripe_customer_id: nil,
        renewal_date: nil,
        manual_status: :high_risk,
        unpaid_invoice?: true
      ),
      # Monthly: renews within days every month, so never highlighted.
      client(
        user_id: 104,
        email: "monthly@hooli.com",
        plan_name: "BUSINESS_PRO",
        interval: "month",
        mrr: 500,
        acv: 6_000,
        renewal_date: Date.add(today(), 5)
      )
    ]
  end

  defp churned do
    [
      %{
        user_id: 201,
        email: "gone@umbrella.com",
        username: "umbrella",
        stripe_customer_id: "cus_umbrella",
        business_reason: :plan,
        last_plan_name: "BUSINESS_MAX",
        interval: "month",
        joined_on: ~D[2025-02-01],
        churned_on: Date.add(today(), -20),
        lost_mrr: 99_900,
        tcv: 899_100,
        current_subscription: "BUNDLE",
        last_entry: %{
          type: "Complaint",
          note: "Too expensive",
          inserted_at: ~U[2026-09-01 10:00:00Z]
        }
      },
      %{
        user_id: 202,
        email: "left@soylent.com",
        username: nil,
        stripe_customer_id: nil,
        business_reason: :business_email,
        last_plan_name: "PRO",
        interval: "year",
        joined_on: ~D[2026-01-10],
        churned_on: Date.add(today(), -90),
        lost_mrr: 4_900,
        tcv: 58_800,
        current_subscription: nil,
        last_entry: nil
      }
    ]
  end

  defp report_mocks(extra_sync_mocks \\ [], churned \\ churned()) do
    monthly = [
      metrics(month: Date.beginning_of_month(today()), source: :computed),
      metrics(
        month: today() |> Date.shift(month: -1) |> Date.beginning_of_month(),
        source: :snapshot,
        client_count: 7,
        # Taken before the segment split.
        segments: nil
      )
    ]

    [
      {Report, [:passthrough],
       [
         page: fn _opts ->
           %{clients: clients(), churned: churned, metrics: metrics(), monthly: monthly}
         end,
         formula_notes: fn _settings -> notes() end
       ]},
      {InvoiceMirror, [:passthrough],
       [
         last_synced_at: fn -> ~U[2026-10-20 06:30:00Z] end,
         coverage: fn _from, _to -> [] end
       ]},
      {SyncJob, [:passthrough],
       [
         subscribe: fn -> :ok end,
         get_state: fn ->
           %{
             status: :idle,
             from_date: nil,
             to_date: nil,
             phase: nil,
             result: nil,
             error: nil,
             task_ref: nil
           }
         end,
         cancel: fn -> :ok end
       ] ++ extra_sync_mocks}
    ]
  end

  defp open_page(conn) do
    {:ok, view, _html} = live(conn, "/admin/business_clients")
    render_async(view, @async_timeout)
    view
  end

  describe "viewing" do
    test "shows the headline metrics, their formulas, the clients and the months" do
      {_user, conn} = sign_in(:role_admin_panel_viewer)

      with_mocks report_mocks() do
        view = open_page(conn)

        assert has_element?(view, "#metric-client-count", "3")
        assert has_element?(view, "#metric-client-churn", "25.0%")
        assert has_element?(view, "#metric-revenue-churn", "$100 of $1,000 MRR")
        assert has_element?(view, "#metric-client-renewal", "3 renewed of 4 due")
        assert has_element?(view, "#metric-revenue-renewal", "$8,000 of $10,000 ACV")
        assert has_element?(view, "#metric-retention", "50.0%")

        # The asterisk carries the formula and links to its footnote.
        assert has_element?(view, ~s(#metric-client-churn a[href="#formula-client_churn"]))
        assert has_element?(view, "#formula-client_churn", "Formula for client_churn")

        assert has_element?(view, "#client-101", "big@acme.com")
        assert has_element?(view, "#client-101", "$900")
        assert has_element?(view, "#client-101", "$10,800")
        assert has_element?(view, ~s(#client-101 a[href="/admin/business_clients/101"]))
        assert has_element?(view, "#client-102", "At Risk")
        assert has_element?(view, "#client-102", "payment failed")

        assert has_element?(
                 view,
                 "#client-102 .badge-warning",
                 Date.to_iso8601(Date.add(today(), 10))
               )

        assert has_element?(view, "#client-103", "High Risk")
        assert has_element?(view, "#client-103", "unpaid invoice")
        refute has_element?(view, "#client-103", "payment failed")
        refute has_element?(view, "#client-102", "unpaid invoice")

        assert has_element?(view, "#last-synced-at", "2026-10-20 06:30")

        month = today() |> Date.shift(month: -1) |> Date.beginning_of_month()
        assert has_element?(view, "#month-#{month}", "snapshot")
        assert has_element?(view, "#month-#{Date.beginning_of_month(today())}", "computed")

        assert has_element?(
                 view,
                 ~s(#export-clients[href="/admin/business_clients/export/clients"])
               )

        assert has_element?(view, "#export-monthly-metrics")
        # Every business-email user is personal data beyond the page: Editor only.
        refute has_element?(view, "#export-business-email-users")

        assert_called(Report.page(as_of: today(), months: 12))
      end
    end

    test "breaks each headline number down by segment" do
      {_user, conn} = sign_in(:role_admin_panel_viewer)

      with_mocks report_mocks() do
        view = open_page(conn)

        # The big number stays the total.
        assert has_element?(view, "#metric-client-count", "3")
        assert has_element?(view, "#metric-client-count-plan", "Business plan:")
        assert has_element?(view, "#metric-client-count-plan .bg-indigo-500")
        assert has_element?(view, "#metric-client-count-plan", "2")
        assert has_element?(view, "#metric-client-count-business_email", "Business email:")
        assert has_element?(view, "#metric-client-count-business_email .bg-amber-500")
        assert has_element?(view, "#metric-client-count-business_email", "1")
        assert has_element?(view, "#metric-mrr", "$1,000")
        assert has_element?(view, "#metric-mrr", "ARR $12,000")
        assert has_element?(view, "#metric-mrr-plan", "$600")
        assert has_element?(view, "#metric-mrr-business_email", "$400")
        assert has_element?(view, "#metric-retention-plan", "-")
        assert has_element?(view, "#metric-client-churn-plan", "0.0% · 0/1")
        assert has_element?(view, "#metric-client-churn-business_email", "1/3")
        assert has_element?(view, "#metric-revenue-churn-business_email", "25.0% · $100/$400")
        assert has_element?(view, "#metric-client-renewal-business_email", "50.0% · 1/2")
        assert has_element?(view, "#metric-revenue-renewal-plan", "100.0% · $7,000/$7,000")
      end
    end

    test "the monthly table switches between the total and a segment" do
      {_user, conn} = sign_in(:role_admin_panel_viewer)

      with_mocks report_mocks() do
        view = open_page(conn)
        current = "#month-#{Date.beginning_of_month(today())}"
        previous = "#month-#{today() |> Date.shift(month: -1) |> Date.beginning_of_month()}"

        assert has_element?(view, ~s(#monthly-segment-total[aria-pressed="true"]))
        assert has_element?(view, current, "(1/4)")
        assert has_element?(view, previous, "(1/4)")

        view |> element("#monthly-segment-plan") |> render_click()

        assert has_element?(view, ~s(#monthly-segment-plan[aria-pressed="true"]))
        assert has_element?(view, current, "(0/1)")
        assert has_element?(view, current, "(2/2)")
        # A snapshot taken before the split has no segment numbers.
        refute has_element?(view, previous, "(1/4)")
        assert has_element?(view, previous, "-")

        view |> element("#monthly-segment-business_email") |> render_click()
        assert has_element?(view, current, "(1/3)")

        view |> element("#monthly-segment-total") |> render_click()
        assert has_element?(view, current, "(1/4)")
      end
    end

    test "shows the recently churned clients and where they are now" do
      {_user, conn} = sign_in(:role_admin_panel_viewer)

      with_mocks report_mocks() do
        view = open_page(conn)

        assert has_element?(view, "#churned-summary", "2 client(s)")
        assert has_element?(view, "#churned-summary", "$1,048")
        assert has_element?(view, ~s(#churned-heading a[href="#formula-churned"]))
        assert has_element?(view, "#formula-churned", "Formula for churned")

        assert has_element?(view, ~s(#churned-201 a[href="/admin/business_clients/201"]))
        assert has_element?(view, "#churned-201", "BUSINESS_MAX")
        assert has_element?(view, "#churned-201", "$999")
        assert has_element?(view, "#churned-201", Date.to_iso8601(Date.add(today(), -20)))
        assert has_element?(view, "#churned-201 #churned-now-on-201", "BUNDLE")
        assert has_element?(view, "#churned-201", "Too expensive")

        assert has_element?(
                 view,
                 ~s(#churned-201 a#churned-stripe-customer-201[href="https://dashboard.stripe.com/customers/cus_umbrella"])
               )

        assert has_element?(view, "#churned-202", "Business email")
        refute has_element?(view, "#churned-now-on-202")
        refute has_element?(view, "#churned-stripe-customer-202")

        assert has_element?(
                 view,
                 ~s(#export-churned[href="/admin/business_clients/export/churned"])
               )
      end
    end

    test "says when nobody churned" do
      {_user, conn} = sign_in(:role_admin_panel_viewer)

      with_mocks report_mocks([], []) do
        view = open_page(conn)

        assert has_element?(view, "#churned-empty")
        assert has_element?(view, "#churned-summary", "0 client(s)")
        refute has_element?(view, "#churned-rows tr[id^=churned-2]")
      end
    end

    test "an editor sees the business-email users export" do
      {_user, conn} = sign_in(:role_admin_panel_editor)

      with_mocks report_mocks() do
        view = open_page(conn)
        assert has_element?(view, "#export-business-email-users")
      end
    end

    test "warns about ranges the invoice import never covered" do
      {_user, conn} = sign_in(:role_admin_panel_viewer)

      mocks =
        Enum.map(report_mocks(), fn
          {InvoiceMirror, opts, fns} ->
            {InvoiceMirror, opts,
             Keyword.put(fns, :coverage, fn _from, _to -> [{~D[2026-01-01], ~D[2026-01-31]}] end)}

          other ->
            other
        end)

      with_mocks mocks do
        view = open_page(conn)
        assert has_element?(view, "#coverage-warning", "2026-01-01 to 2026-01-31")
      end
    end

    test "links each client to its Stripe customer in a new tab" do
      {_user, conn} = sign_in(:role_admin_panel_viewer)

      with_mocks report_mocks() do
        view = open_page(conn)

        assert has_element?(
                 view,
                 ~s(#client-101 a#stripe-customer-101[href="https://dashboard.stripe.com/customers/cus_acme"][target="_blank"][rel="noopener noreferrer"])
               )

        # No customer id, no link.
        refute has_element?(view, "#stripe-customer-103")
      end
    end

    test "highlights only renewals on a renewal interval, by default yearly" do
      {_user, conn} = sign_in(:role_admin_panel_viewer)

      with_mocks report_mocks() do
        view = open_page(conn)

        assert has_element?(view, "#clients-count", "Yearly renewals within 30 days")

        assert has_element?(
                 view,
                 "#client-102 .badge-warning",
                 Date.to_iso8601(Date.add(today(), 10))
               )

        # A monthly renewal is always within 30 days: shown plain.
        assert has_element?(view, "#client-104", Date.to_iso8601(Date.add(today(), 5)))
        refute has_element?(view, "#client-104 .badge-warning")
      end
    end

    test "shows the later of web and API activity with its source" do
      {_user, conn} = sign_in(:role_admin_panel_viewer)

      with_mocks report_mocks() do
        view = open_page(conn)

        assert has_element?(view, "#client-101", "2026-10-21 08:00")
        assert has_element?(view, "#client-101 .badge", "API")
        assert has_element?(view, "#client-102 .badge", "web")
      end
    end

    test "an editor gets a Log link to the client's add-entry form; a viewer does not" do
      {_user, conn} = sign_in(:role_admin_panel_editor)

      with_mocks report_mocks() do
        view = open_page(conn)

        assert has_element?(
                 view,
                 ~s(#log-client-102[href="/admin/business_clients/102#add-entry-panel"])
               )
      end

      {_user, conn} = sign_in(:role_admin_panel_viewer)

      with_mocks report_mocks() do
        view = open_page(conn)
        refute has_element?(view, "#log-client-102")
      end
    end

    test "the formula notes start collapsed; an asterisk or the summary opens them" do
      {_user, conn} = sign_in(:role_admin_panel_viewer)

      with_mocks report_mocks() do
        view = open_page(conn)

        assert has_element?(view, "details#formula-notes")
        refute has_element?(view, "#formula-notes[open]")

        view
        |> element(~s(#metric-client-churn a[href="#formula-client_churn"]))
        |> render_click()

        assert has_element?(view, "#formula-notes[open]")

        view |> element("#formula-notes-toggle") |> render_click()
        refute has_element?(view, "#formula-notes[open]")

        view |> element("#formula-notes-toggle") |> render_click()
        assert has_element?(view, "#formula-notes[open]")
      end
    end
  end

  describe "filtering and sorting" do
    test "filters by status, reason, query and renewal window" do
      {_user, conn} = sign_in(:role_admin_panel_viewer)

      with_mocks report_mocks() do
        view = open_page(conn)

        view |> form("#client-filters", %{"status" => "at_risk"}) |> render_change()
        assert has_element?(view, "#client-102")
        refute has_element?(view, "#client-101")

        view
        |> form("#client-filters", %{"status" => "all", "reason" => "override"})
        |> render_change()

        assert has_element?(view, "#client-103")
        refute has_element?(view, "#client-102")

        view
        |> form("#client-filters", %{"reason" => "all", "query" => "GLOBEX"})
        |> render_change()

        assert has_element?(view, "#client-102")
        refute has_element?(view, "#client-101")

        view
        |> form("#client-filters", %{"query" => "", "renewal_within" => "30"})
        |> render_change()

        assert has_element?(view, "#client-102")
        assert has_element?(view, "#client-104")
        refute has_element?(view, "#client-101")
        refute has_element?(view, "#client-103")

        view
        |> form("#client-filters", %{"plan" => "MAX", "renewal_within" => ""})
        |> render_change()

        assert has_element?(view, "#client-103")
        refute has_element?(view, "#client-102")
        assert has_element?(view, "#clients-count", "Showing 1 of 4")

        view
        |> form("#client-filters", %{"plan" => "all", "query" => "nobody-matches"})
        |> render_change()

        assert row_ids(view) == []
        assert has_element?(view, "#clients-empty")

        view |> element("#clear-filters") |> render_click()
        assert has_element?(view, "#client-101")
        assert has_element?(view, "#client-102")
        assert has_element?(view, "#client-103")
      end
    end

    test "sorts by MRR by default and by renewal date on request" do
      {_user, conn} = sign_in(:role_admin_panel_viewer)

      with_mocks report_mocks() do
        view = open_page(conn)

        assert row_ids(view) == ["client-101", "client-102", "client-103", "client-104"]

        view |> element("#sort-mrr") |> render_click()
        assert row_ids(view) == ["client-104", "client-103", "client-102", "client-101"]

        view |> element("#sort-renewal_date") |> render_click()
        # Soonest first, the client without a renewal date last.
        assert row_ids(view) == ["client-104", "client-102", "client-101", "client-103"]
      end
    end
  end

  describe "invoice re-import" do
    test "a viewer sees no re-import control and cannot start one" do
      {_user, conn} = sign_in(:role_admin_panel_viewer)

      with_mocks report_mocks(start_job: fn _from, _to, _user_id -> :ok end) do
        view = open_page(conn)

        refute has_element?(view, "#resync-form")

        render_hook(view, "resync", %{"from" => "2026-01-01", "to" => "2026-02-01"})
        assert render(view) =~ "needs the Editor role"
        refute called(SyncJob.start_job(:_, :_, :_))
      end
    end

    test "an editor starts a re-import of the chosen range" do
      {user, conn} = sign_in(:role_admin_panel_editor)
      user_id = user.id

      with_mocks report_mocks(start_job: fn _from, _to, _user_id -> :ok end) do
        view = open_page(conn)

        view
        |> form("#resync-form", %{"from" => "2025-01-01", "to" => "2025-06-30"})
        |> render_submit()

        assert_called(SyncJob.start_job(~D[2025-01-01], ~D[2025-06-30], user_id))
      end
    end

    test "rejects an inverted or too long range" do
      {_user, conn} = sign_in(:role_admin_panel_editor)

      with_mocks report_mocks(start_job: fn _from, _to, _user_id -> :ok end) do
        view = open_page(conn)

        view
        |> form("#resync-form", %{"from" => "2025-06-30", "to" => "2025-01-01"})
        |> render_submit()

        assert render(view) =~ "must not be after the end date"

        view
        |> form("#resync-form", %{"from" => "2021-01-01", "to" => "2025-01-02"})
        |> render_submit()

        assert render(view) =~ "at most 3 years"
        refute called(SyncJob.start_job(:_, :_, :_))
      end
    end

    test "reports an import that could not start" do
      {_user, conn} = sign_in(:role_admin_panel_editor)

      with_mocks report_mocks(
                   start_job: fn _from, _to, _user_id -> {:error, :already_running} end
                 ) do
        view = open_page(conn)

        view
        |> form("#resync-form", %{"from" => "2025-01-01", "to" => "2025-06-30"})
        |> render_submit()

        assert render(view) =~ "An import is already running"
      end
    end

    test "a finished import reloads the numbers once, however often it is broadcast" do
      {_user, conn} = sign_in(:role_admin_panel_viewer)

      done = %{
        status: :done,
        from_date: ~D[2026-01-01],
        to_date: ~D[2026-02-01],
        phase: :done,
        result: %{invoices_upserted: 12},
        error: nil,
        task_ref: nil
      }

      with_mocks report_mocks() do
        view = open_page(conn)
        assert :meck.num_calls(Report, :page, :_) == 1

        send(view.pid, {:sync_update, done})
        send(view.pid, {:sync_update, done})
        render_async(view, @async_timeout)

        assert :meck.num_calls(Report, :page, :_) == 2
      end
    end

    test "a finished import refreshes the last synced time" do
      {_user, conn} = sign_in(:role_admin_panel_viewer)

      with_mocks report_mocks() do
        view = open_page(conn)

        send(
          view.pid,
          {:sync_update,
           %{
             status: :done,
             from_date: ~D[2026-01-01],
             to_date: ~D[2026-02-01],
             phase: :done,
             result: %{invoices_upserted: 12},
             error: nil,
             task_ref: nil
           }}
        )

        assert render(view) =~ "Import finished: 12 invoices upserted."
      end
    end
  end

  describe "settings" do
    test "collapsed and read-only for everyone who is not an owner" do
      for role <- [:role_admin_panel_viewer, :role_admin_panel_editor] do
        {_user, conn} = sign_in(role)

        with_mocks report_mocks() do
          view = open_page(conn)

          assert has_element?(view, "details#settings-section")
          refute has_element?(view, "#settings-section[open]")
          assert has_element?(view, "#settings-fields[disabled]")
          assert has_element?(view, "#settings-read-only")
          refute has_element?(view, "#edit-settings")
          refute has_element?(view, "#save-settings")

          view |> element("#settings-toggle") |> render_click()
          assert has_element?(view, "#settings-section[open]")

          # Unlocking is checked on the server too.
          render_hook(view, "edit_settings", %{})
          assert render(view) =~ "needs the Owner role"
          assert has_element?(view, "#settings-fields[disabled]")
        end
      end
    end

    test "an owner unlocks the settings with Edit and Cancel locks them again" do
      {_user, conn} = sign_in(:role_admin_panel_owner)

      with_mocks report_mocks() do
        view = open_page(conn)

        assert has_element?(view, "#settings-fields[disabled]")
        refute has_element?(view, "#save-settings")

        view |> element("#edit-settings") |> render_click()

        assert has_element?(view, "#settings-section[open]")
        refute has_element?(view, "#settings-fields[disabled]")
        assert has_element?(view, "#save-settings")

        view |> element("#cancel-settings") |> render_click()

        assert has_element?(view, "#settings-fields[disabled]")
        assert has_element?(view, "#edit-settings")
        assert BusinessClients.settings().churn_window_months == 12
      end
    end

    test "an owner validates and saves the settings" do
      {user, conn} = sign_in(:role_admin_panel_owner)

      with_mocks report_mocks() do
        view = open_page(conn)

        assert has_element?(view, "#settings-last-change", "defaults apply")

        view |> element("#edit-settings") |> render_click()

        html =
          view
          |> form("#settings-form", %{"settings" => %{"churn_window_months" => "0"}})
          |> render_change()

        assert html =~ "must be greater than 0"

        view
        |> form("#settings-form", %{
          "settings" => %{
            "churn_window_months" => "6",
            "business_email_product_ids" => "2, 5",
            "issue_types" => "Complaint\nRetention action\nCall",
            "types_without_severity" => "Retention action",
            "retention_action_type" => "Retention action"
          }
        })
        |> render_submit()

        settings = BusinessClients.settings()
        assert settings.churn_window_months == 6
        assert settings.business_email_product_ids == [2, 5]
        assert settings.issue_types == ["Complaint", "Retention action", "Call"]
        assert has_element?(view, "#settings-last-change", user.email)
        # Saved: back to read-only.
        assert has_element?(view, "#settings-fields[disabled]")
        assert has_element?(view, "#edit-settings")
      end
    end

    test "a non-owner cannot save the settings even by sending the event" do
      {_user, conn} = sign_in(:role_admin_panel_editor)

      with_mocks report_mocks() do
        view = open_page(conn)

        render_hook(view, "save_settings", %{"settings" => %{"churn_window_months" => "3"}})

        assert render(view) =~ "needs the Owner role"
        assert BusinessClients.settings().churn_window_months == 12
      end
    end
  end

  defp today, do: Date.utc_today()

  defp row_ids(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(~s(#clients-rows tr[id^="client-"]))
    |> LazyHTML.attribute("id")
  end
end
