defmodule SanbaseWeb.Admin.BusinessClientsControllerTest do
  use SanbaseWeb.ConnCase, async: false

  @moduletag capture_log: true

  import Mock
  import Sanbase.Factory

  alias Sanbase.Billing.BusinessClients.Report

  setup do
    {:ok, conn: sign_in(:role_admin_panel_viewer)}
  end

  defp sign_in(role_factory) do
    user = insert(:user)
    role = insert(role_factory)
    {:ok, _user_role} = Sanbase.Accounts.UserRole.create(user.id, role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)
    Plug.Test.init_test_session(build_conn(), jwt_tokens)
  end

  @client %{
    user_id: 7,
    email: "=cmd@acme.com",
    username: "acme",
    stripe_customer_id: "cus_7",
    plan_name: "BUSINESS_PRO",
    product_id: 2,
    interval: "year",
    business_reason: :plan,
    mrr: 41_667,
    acv: 500_004,
    tcv: 1_000_008,
    start_date: ~D[2024-01-01],
    renewal_date: ~D[2027-01-01],
    paid_by: %{
      card: 0,
      wire: 1_000_008,
      crypto: 0,
      san_burn: 0,
      stripe_credit: -1_250,
      other: 0,
      unknown: 0,
      out_of_band: 0
    },
    subscription_status: "active",
    failed_payment?: false,
    unpaid_invoice?: true,
    api_calls: 10,
    api_calls_prev: nil,
    last_active_at: ~U[2026-10-01 00:00:00Z],
    last_web_active_at: nil,
    last_api_call_at: ~U[2026-10-01 00:00:00Z],
    manual_status: :at_risk,
    open_entries_count: 1,
    retention_action?: true,
    override: nil
  }

  @month %{
    month: ~D[2026-10-01],
    source: :snapshot,
    as_of: ~D[2026-10-01],
    window: %{from: ~D[2025-10-01], to: ~D[2026-10-01]},
    client_count: 12,
    at_risk_count: 2,
    retention_action_pct: 50.0,
    client_churn: %{rate: 0.25, lost: 1, base: 4},
    revenue_churn: %{rate: 0.1, lost_mrr: 10_050, base_mrr: 100_500, expansion_mrr: 0},
    client_renewal: %{rate: nil, renewed: 0, due: 0},
    revenue_renewal: %{rate: nil, renewed_acv: 0, due_acv: 0},
    segments: %{
      plan: %{
        client_count: 9,
        at_risk_count: 0,
        retention_action_pct: nil,
        client_churn: %{rate: 0.0, lost: 0, base: 1},
        revenue_churn: %{rate: 0.0, lost_mrr: 0, base_mrr: 90_000, expansion_mrr: 0},
        client_renewal: %{rate: nil, renewed: 0, due: 0},
        revenue_renewal: %{rate: nil, renewed_acv: 0, due_acv: 0}
      },
      business_email: %{
        client_count: 3,
        at_risk_count: 2,
        retention_action_pct: 50.0,
        client_churn: %{rate: 1 / 3, lost: 1, base: 3},
        revenue_churn: %{rate: 1.0, lost_mrr: 10_050, base_mrr: 10_500, expansion_mrr: 0},
        client_renewal: %{rate: nil, renewed: 0, due: 0},
        revenue_renewal: %{rate: nil, renewed_acv: 0, due_acv: 0}
      }
    },
    settings: %{}
  }

  @churned %{
    user_id: 8,
    email: "+gone@acme.com",
    username: "gone",
    stripe_customer_id: "cus_8",
    business_reason: :plan,
    last_plan_name: "BUSINESS_MAX",
    interval: "month",
    joined_on: ~D[2025-03-01],
    churned_on: ~D[2026-08-01],
    lost_mrr: 99_900,
    tcv: 599_400,
    current_subscription: "BUNDLE",
    last_entry: %{type: "Complaint", note: "=HYPERLINK(1)", inserted_at: ~U[2026-07-01 00:00:00Z]}
  }

  defp report_mock do
    {Report, [:passthrough],
     [
       list_clients: fn _opts -> [@client] end,
       monthly_metrics: fn _opts ->
         # The second month was snapshotted before the segment split.
         [@month, %{@month | month: ~D[2026-09-01], segments: nil}]
       end,
       churned_clients: fn _opts -> [@churned] end,
       business_email_users: fn ->
         [
           %{
             user_id: 9,
             email: "cto@initech.com",
             username: nil,
             registered_at: ~N[2025-05-05 10:00:00],
             plan_name: nil,
             paying?: false
           }
         ]
       end
     ]}
  end

  test "exports the clients with amounts in dollars", %{conn: conn} do
    with_mocks [report_mock()] do
      conn = get(conn, ~p"/admin/business_clients/export/clients")

      assert response_content_type(conn, :csv)
      assert get_resp_header(conn, "content-disposition") |> hd() =~ "business_clients_"

      [header, row] = conn |> response(200) |> NimbleCSV.RFC4180.parse_string(skip_headers: false)

      record = Enum.zip(header, row) |> Map.new()

      assert record["user_id"] == "7"
      # A leading = would run as a spreadsheet formula.
      assert record["email"] == "'=cmd@acme.com"
      assert record["mrr_usd"] == "416.67"
      assert record["acv_usd"] == "5000.04"
      assert record["paid_by_wire_usd"] == "10000.08"
      assert record["paid_by_stripe_credit_usd"] == "-12.50"
      assert record["renewal_date"] == "2027-01-01"
      assert record["manual_status"] == "at_risk"
      assert record["api_calls_prev"] == ""
      assert record["retention_action"] == "true"
      assert record["failed_payment"] == "false"
      assert record["unpaid_invoice"] == "true"
      assert record["last_api_call_at"] == "2026-10-01T00:00:00Z"
      assert record["last_web_active_at"] == ""
    end
  end

  test "guards a leading tab or carriage return against formula injection", %{conn: conn} do
    rows = [Map.put(@client, :email, "\t=cmd"), Map.merge(@client, %{email: "\r=cmd"})]

    with_mock Report, [:passthrough], list_clients: fn _opts -> rows end do
      conn = get(conn, ~p"/admin/business_clients/export/clients")

      [header | records] =
        conn |> response(200) |> NimbleCSV.RFC4180.parse_string(skip_headers: false)

      email_index = Enum.find_index(header, &(&1 == "email"))
      assert Enum.map(records, &Enum.at(&1, email_index)) == ["'\t=cmd", "'\r=cmd"]
    end
  end

  test "a viewer cannot export the business-email users", %{conn: conn} do
    with_mocks [report_mock()] do
      conn = get(conn, ~p"/admin/business_clients/export/business_email_users")

      assert redirected_to(conn) == "/admin/business_clients"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "needs the Editor role"
      refute called(Report.business_email_users())
    end
  end

  test "an editor exports the business-email users" do
    conn = sign_in(:role_admin_panel_editor)

    with_mocks [report_mock()] do
      conn = get(conn, ~p"/admin/business_clients/export/business_email_users")
      body = response(conn, 200)

      assert body =~ "user_id,email,username,registered_at,plan_name,paying"
      assert body =~ "9,cto@initech.com,,2025-05-05T10:00:00,,false"
    end
  end

  test "exports the monthly metrics", %{conn: conn} do
    with_mocks [report_mock()] do
      conn = get(conn, ~p"/admin/business_clients/export/monthly_metrics")

      [header, row, old_row] =
        conn |> response(200) |> NimbleCSV.RFC4180.parse_string(skip_headers: false)

      record = Enum.zip(header, row) |> Map.new()

      assert record["month"] == "2026-10-01"
      assert record["source"] == "snapshot"
      assert record["client_churn_rate"] == "0.2500"
      assert record["lost_mrr_usd"] == "100.50"
      assert record["client_renewal_rate"] == ""

      assert record["plan_client_count"] == "9"
      assert record["plan_base_mrr_usd"] == "900.00"
      assert record["email_client_count"] == "3"
      assert record["email_clients_lost"] == "1"
      assert record["email_client_base"] == "3"
      assert record["email_client_churn_rate"] == "0.3333"
      assert record["email_lost_mrr_usd"] == "100.50"
      assert length(header) == 4 + 16 * 3

      old = Enum.zip(header, old_row) |> Map.new()
      assert old["client_count"] == "12"
      assert old["plan_client_count"] == ""
      assert old["email_lost_mrr_usd"] == ""
    end
  end

  test "exports the recently churned clients", %{conn: conn} do
    with_mocks [report_mock()] do
      conn = get(conn, ~p"/admin/business_clients/export/churned")

      assert response_content_type(conn, :csv)
      assert get_resp_header(conn, "content-disposition") |> hd() =~ "business_clients_churned_"

      [header, row] = conn |> response(200) |> NimbleCSV.RFC4180.parse_string(skip_headers: false)
      record = Enum.zip(header, row) |> Map.new()

      assert record["user_id"] == "8"
      assert record["email"] == "'+gone@acme.com"
      assert record["last_plan_name"] == "BUSINESS_MAX"
      assert record["joined_on"] == "2025-03-01"
      assert record["churned_on"] == "2026-08-01"
      assert record["lost_mrr_usd"] == "999.00"
      assert record["tcv_usd"] == "5994.00"
      assert record["current_subscription"] == "BUNDLE"
      assert record["last_entry_type"] == "Complaint"
      assert record["last_entry_note"] == "'=HYPERLINK(1)"
      assert_called(Report.churned_clients(as_of: Date.utc_today()))
    end
  end

  test "redirects on an unknown export", %{conn: conn} do
    conn = get(conn, ~p"/admin/business_clients/export/nope")
    assert redirected_to(conn) == "/admin/business_clients"
  end
end
