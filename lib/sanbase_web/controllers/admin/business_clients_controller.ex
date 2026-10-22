defmodule SanbaseWeb.Admin.BusinessClientsController do
  @moduledoc """
  CSV exports for the Business Clients admin page: the clients as of today, the
  recently churned clients, every user with a business email, and the monthly churn
  and renewal numbers, in total and per segment (`plan_` and `email_` columns). Amounts
  are in dollars with two decimals, so a spreadsheet does not have to divide by 100.
  """

  use SanbaseWeb, :controller

  alias Sanbase.Admin.Permissions
  alias Sanbase.Billing.BusinessClients

  @paid_by_keys [:card, :wire, :crypto, :san_burn, :stripe_credit, :other, :unknown, :out_of_band]

  @client_headers ~w(user_id email username stripe_customer_id plan_name product_id interval
                     business_reason override mrr_usd acv_usd tcv_usd start_date renewal_date) ++
                    Enum.map(@paid_by_keys, &"paid_by_#{&1}_usd") ++
                    ~w(subscription_status failed_payment unpaid_invoice api_calls
                       api_calls_prev last_active_at last_web_active_at last_api_call_at
                       manual_status open_entries_count retention_action)

  @churned_headers ~w(user_id email username stripe_customer_id business_reason
                      last_plan_name interval joined_on churned_on lost_mrr_usd tcv_usd
                      current_subscription last_entry_type last_entry_note)

  @business_email_headers ~w(user_id email username registered_at plan_name paying)

  @metric_headers ~w(client_count at_risk_count retention_action_pct client_churn_rate
                     clients_lost client_base revenue_churn_rate lost_mrr_usd base_mrr_usd
                     expansion_mrr_usd client_renewal_rate clients_renewed clients_due
                     revenue_renewal_rate renewed_acv_usd due_acv_usd)

  # The totals, then the same columns per segment.
  @segment_prefixes [plan: "plan_", business_email: "email_"]

  @monthly_headers ~w(month source window_from window_to) ++
                     @metric_headers ++
                     Enum.flat_map(@segment_prefixes, fn {_segment, prefix} ->
                       Enum.map(@metric_headers, &(prefix <> &1))
                     end)

  def export(conn, %{"what" => "clients"}) do
    today = Date.utc_today()
    rows = BusinessClients.list_clients(as_of: today)

    send_csv(
      conn,
      "business_clients_#{today}.csv",
      @client_headers,
      Enum.map(rows, &client_row/1)
    )
  end

  def export(conn, %{"what" => "churned"}) do
    today = Date.utc_today()
    rows = BusinessClients.churned_clients(as_of: today)

    send_csv(
      conn,
      "business_clients_churned_#{today}.csv",
      @churned_headers,
      Enum.map(rows, &churned_row/1)
    )
  end

  # Every user with a business-domain email, paying or not - personal data beyond what
  # the page shows, so it needs the Editor role. The other exports are the page's own
  # numbers and any Admin Panel role may download them.
  def export(conn, %{"what" => "business_email_users"}) do
    if Permissions.can?(:edit, roles: conn.assigns[:current_user_role_names] || []) do
      rows = BusinessClients.business_email_users()

      send_csv(
        conn,
        "business_email_users_#{Date.utc_today()}.csv",
        @business_email_headers,
        Enum.map(rows, &business_email_row/1)
      )
    else
      conn
      |> put_flash(:error, "Exporting the business-email users needs the Editor role.")
      |> redirect(to: ~p"/admin/business_clients")
    end
  end

  def export(conn, %{"what" => "monthly_metrics"}) do
    rows = BusinessClients.monthly_metrics(months: 12)

    send_csv(
      conn,
      "business_metrics_monthly_#{Date.utc_today()}.csv",
      @monthly_headers,
      Enum.map(rows, &monthly_row/1)
    )
  end

  def export(conn, _params) do
    conn
    |> put_flash(:error, "Unknown export.")
    |> redirect(to: ~p"/admin/business_clients")
  end

  defp client_row(c) do
    [
      c.user_id,
      c.email,
      c.username,
      c.stripe_customer_id,
      c.plan_name,
      c.product_id,
      c.interval,
      c.business_reason,
      c.override,
      usd(c.mrr),
      usd(c.acv),
      usd(c.tcv),
      date(c.start_date),
      date(c.renewal_date)
    ] ++
      Enum.map(@paid_by_keys, &usd(Map.get(c.paid_by || %{}, &1, 0))) ++
      [
        c.subscription_status,
        c.failed_payment?,
        c.unpaid_invoice?,
        c.api_calls,
        c.api_calls_prev,
        datetime(c.last_active_at),
        datetime(c.last_web_active_at),
        datetime(c.last_api_call_at),
        c.manual_status,
        c.open_entries_count,
        c.retention_action?
      ]
  end

  defp churned_row(c) do
    [
      c.user_id,
      c.email,
      c.username,
      c.stripe_customer_id,
      c.business_reason,
      c.last_plan_name,
      c.interval,
      date(c.joined_on),
      date(c.churned_on),
      usd(c.lost_mrr),
      usd(c.tcv),
      c.current_subscription,
      c.last_entry && c.last_entry.type,
      c.last_entry && c.last_entry.note
    ]
  end

  defp business_email_row(u) do
    [u.user_id, u.email, u.username, datetime(u.registered_at), u.plan_name, u.paying?]
  end

  defp monthly_row(m) do
    segments = Map.get(m, :segments)

    [date(m.month), m.source, date(m.window.from), date(m.window.to)] ++
      metric_cells(m) ++
      Enum.flat_map(@segment_prefixes, fn {segment, _prefix} ->
        metric_cells(segments && Map.get(segments, segment))
      end)
  end

  # A month snapshotted before the split has no segments: empty cells.
  defp metric_cells(nil), do: Enum.map(@metric_headers, fn _ -> nil end)

  defp metric_cells(m) do
    [
      m.client_count,
      m.at_risk_count,
      m.retention_action_pct,
      m.client_churn.rate,
      m.client_churn.lost,
      m.client_churn.base,
      m.revenue_churn.rate,
      usd(m.revenue_churn.lost_mrr),
      usd(m.revenue_churn.base_mrr),
      usd(m.revenue_churn.expansion_mrr),
      m.client_renewal.rate,
      m.client_renewal.renewed,
      m.client_renewal.due,
      m.revenue_renewal.rate,
      usd(m.revenue_renewal.renewed_acv),
      usd(m.revenue_renewal.due_acv)
    ]
  end

  defp send_csv(conn, filename, headers, rows) do
    csv =
      NimbleCSV.RFC4180.dump_to_iodata([
        headers | Enum.map(rows, &Enum.map(&1, fn v -> cell(v) end))
      ])

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, csv)
  end

  defp date(nil), do: nil
  defp date(%Date{} = date), do: Date.to_iso8601(date)
  defp date(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d")

  defp datetime(nil), do: nil
  defp datetime(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp datetime(other), do: to_string(other)

  # Cents in, dollars out. Tagged so a negative amount is not mistaken for a formula.
  defp usd(cents) when is_number(cents),
    do: {:number, :erlang.float_to_binary(cents / 100, decimals: 2)}

  defp usd(%Decimal{} = cents),
    do: {:number, cents |> Decimal.div(100) |> Decimal.round(2) |> Decimal.to_string(:normal)}

  defp usd(_cents), do: nil

  defp cell(nil), do: ""
  defp cell({:number, value}), do: value
  defp cell(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 4)

  # Guard against spreadsheet formula injection: emails, usernames and plan names are
  # user or Stripe input, and a leading =, +, -, @, tab or carriage return can run as
  # a formula (OWASP CSV injection).
  defp cell(value) when is_binary(value) do
    if String.starts_with?(value, ["=", "+", "-", "@", "\t", "\r"]),
      do: "'" <> value,
      else: value
  end

  defp cell(value), do: to_string(value)
end
