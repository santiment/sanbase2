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

  @today Date.utc_today()

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
        renewal_date: Date.add(@today, 200),
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
        api_calls: 1_200,
        api_calls_prev: 900,
        last_active_at: ~U[2026-10-20 10:00:00Z],
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
        as_of: @today,
        window: %{from: Date.add(@today, -365), to: @today},
        client_count: 3,
        at_risk_count: 1,
        retention_action_pct: 50.0,
        client_churn: %{rate: 0.25, lost: 1, base: 4},
        revenue_churn: %{rate: 0.1, lost_mrr: 10_000, base_mrr: 100_000, expansion_mrr: 5_000},
        client_renewal: %{rate: 0.75, renewed: 3, due: 4},
        revenue_renewal: %{rate: 0.8, renewed_acv: 800_000, due_acv: 1_000_000},
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
      client(user_id: 101, email: "big@acme.com", mrr: 90_000, acv: 1_080_000),
      client(
        user_id: 102,
        email: "risky@globex.com",
        username: "globex",
        plan_name: "PRO",
        business_reason: :business_email,
        mrr: 5_000,
        acv: 60_000,
        renewal_date: Date.add(@today, 10),
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
        renewal_date: nil,
        manual_status: :high_risk
      )
    ]
  end

  defp report_mocks(extra_sync_mocks \\ []) do
    monthly = [
      metrics(month: Date.beginning_of_month(@today), source: :computed),
      metrics(
        month: @today |> Date.shift(month: -1) |> Date.beginning_of_month(),
        source: :snapshot,
        client_count: 7
      )
    ]

    [
      {Report, [:passthrough],
       [
         page: fn _opts -> %{clients: clients(), metrics: metrics(), monthly: monthly} end,
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
                 Date.to_iso8601(Date.add(@today, 10))
               )

        assert has_element?(view, "#client-103", "High Risk")

        assert has_element?(view, "#last-synced-at", "2026-10-20 06:30")

        month = @today |> Date.shift(month: -1) |> Date.beginning_of_month()
        assert has_element?(view, "#month-#{month}", "snapshot")
        assert has_element?(view, "#month-#{Date.beginning_of_month(@today)}", "computed")

        assert has_element?(
                 view,
                 ~s(#export-clients[href="/admin/business_clients/export/clients"])
               )

        assert has_element?(view, "#export-monthly-metrics")
        # Every business-email user is personal data beyond the page: Editor only.
        refute has_element?(view, "#export-business-email-users")

        assert_called(Report.page(as_of: @today, months: 12))
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
        refute has_element?(view, "#client-101")
        refute has_element?(view, "#client-103")

        view
        |> form("#client-filters", %{"plan" => "MAX", "renewal_within" => ""})
        |> render_change()

        assert has_element?(view, "#client-103")
        refute has_element?(view, "#client-102")
        assert has_element?(view, "#clients-count", "Showing 1 of 3")

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

        assert row_ids(view) == ["client-101", "client-102", "client-103"]

        view |> element("#sort-mrr") |> render_click()
        assert row_ids(view) == ["client-103", "client-102", "client-101"]

        view |> element("#sort-renewal_date") |> render_click()
        # Soonest first, the client without a renewal date last.
        assert row_ids(view) == ["client-102", "client-101", "client-103"]
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
    test "only an owner sees the settings form" do
      for role <- [:role_admin_panel_viewer, :role_admin_panel_editor] do
        {_user, conn} = sign_in(role)

        with_mocks report_mocks() do
          view = open_page(conn)
          refute has_element?(view, "#settings-form")
        end
      end
    end

    test "an owner validates and saves the settings" do
      {user, conn} = sign_in(:role_admin_panel_owner)

      with_mocks report_mocks() do
        view = open_page(conn)

        assert has_element?(view, "#settings-form")
        assert has_element?(view, "#settings-last-change", "defaults apply")

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

  defp row_ids(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(~s(#clients-rows tr[id^="client-"]))
    |> LazyHTML.attribute("id")
  end
end
