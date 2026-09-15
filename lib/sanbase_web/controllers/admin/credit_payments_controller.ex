defmodule SanbaseWeb.Admin.CreditPaymentsController do
  @moduledoc """
  CSV export for the credit payments admin page. Re-runs the Stripe report for the
  given range and filters and streams it as a download, so the numbers behind the
  table can go straight into a spreadsheet.
  """

  use SanbaseWeb, :controller

  alias Sanbase.Billing.CreditPayments
  alias Sanbase.Billing.CreditPayments.Store

  @invoice_headers ~w(number invoice_id user_id customer_email stripe_customer_id date
                      total_usd credit_paid_usd card_paid_usd out_of_band_usd source
                      source_note paid_out_of_band stripe_invoice_url stripe_customer_url)

  @grant_headers ~w(date user_id customer_email stripe_customer_id amount_usd source
                    internal_note stripe_customer_url)

  def export(conn, params) do
    with {:ok, from} <- parse_date(params["from"]),
         {:ok, to} <- parse_date(params["to"]) do
      # The mirror, not Stripe: an export has to be instant, and it must show exactly
      # the rows the page showed.
      report = Store.range_report(from, to)
      what = params["what"] || "invoices"

      {filename, csv} = build_export(what, report, params, from, to)

      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> send_resp(200, csv)
    else
      _ ->
        conn
        |> put_flash(:error, "Invalid date range for the export.")
        |> redirect(to: ~p"/admin/credit_payments")
    end
  end

  defp build_export("grants", report, _params, from, to) do
    {"credit_grants_#{from}_#{to}.csv", grants_csv(report.grants)}
  end

  defp build_export(_invoices, report, params, from, to) do
    rows =
      CreditPayments.filter_invoices(report.invoices,
        source: CreditPayments.parse_source(params["source"]),
        query: params["query"] || ""
      )

    {"credit_payments_#{from}_#{to}.csv", invoices_csv(rows)}
  end

  defp invoices_csv(rows) do
    data =
      Enum.map(rows, fn row ->
        [
          row.number,
          row.id,
          row.user_id,
          row.email,
          row.customer,
          date(row.created),
          usd(row.total),
          usd(row.credit_applied),
          usd(row.amount_paid),
          if(row.paid_out_of_band, do: usd(row.total), else: usd(0)),
          row.source,
          row.source_note,
          row.paid_out_of_band,
          CreditPayments.stripe_invoice_url(row.id),
          row.customer && CreditPayments.stripe_customer_url(row.customer)
        ]
        |> Enum.map(&cell/1)
      end)

    NimbleCSV.RFC4180.dump_to_iodata([@invoice_headers | data])
  end

  defp grants_csv(rows) do
    data =
      Enum.map(rows, fn row ->
        [
          date(row.created),
          row.user_id,
          row.email,
          row.customer,
          usd(row.amount),
          row.source,
          row.description,
          row.customer && CreditPayments.stripe_customer_url(row.customer)
        ]
        |> Enum.map(&cell/1)
      end)

    NimbleCSV.RFC4180.dump_to_iodata([@grant_headers | data])
  end

  defp parse_date(nil), do: :error
  defp parse_date(date), do: Date.from_iso8601(date)

  defp date(nil), do: ""
  defp date(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d")

  # Cents in, dollars out - a spreadsheet should not have to divide by 100.
  defp usd(cents) when is_integer(cents), do: :erlang.float_to_binary(cents / 100, decimals: 2)
  defp usd(_cents), do: ""

  defp cell(nil), do: ""

  # Guard against spreadsheet formula injection: a leading =, +, - or @ in a
  # value written by hand in Stripe can be executed as a formula.
  defp cell(value) when is_binary(value) do
    if String.starts_with?(value, ["=", "+", "-", "@"]), do: "'" <> value, else: value
  end

  defp cell(value), do: to_string(value)
end
