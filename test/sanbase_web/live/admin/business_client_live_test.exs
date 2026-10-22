defmodule SanbaseWeb.Admin.BusinessClientLiveTest do
  use SanbaseWeb.ConnCase, async: false

  @moduletag capture_log: true

  @async_timeout 5_000

  import Mock
  import Phoenix.LiveViewTest
  import Sanbase.Factory

  alias Sanbase.Accounts.UserRole
  alias Sanbase.Billing.BusinessClients
  alias Sanbase.Billing.BusinessClients.{LogEntry, Report}
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
