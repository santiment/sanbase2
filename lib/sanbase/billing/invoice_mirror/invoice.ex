defmodule Sanbase.Billing.InvoiceMirror.Invoice do
  @moduledoc ~s"""
  A Stripe invoice, mirrored locally whatever paid it - card, account credit or a
  payment marked as received outside Stripe.

  Amounts are in cents, as Stripe reports them. `total_excluding_tax` is what revenue
  is counted from. `credit_applied` is how much of the invoice the customer's credit
  balance covered, the same value `Sanbase.Billing.CreditPayments.credit_applied/1`
  computes, so the two mirrors agree on which invoices were paid by credit.
  """

  use Ecto.Schema

  import Ecto.Changeset

  schema "stripe_invoices" do
    field(:stripe_invoice_id, :string)
    field(:invoice_number, :string)
    field(:stripe_customer_id, :string)
    field(:customer_email, :string)
    field(:stripe_subscription_id, :string)
    field(:status, :string)
    field(:billing_reason, :string)
    field(:currency, :string)
    field(:invoiced_at, :utc_datetime)
    field(:paid_at, :utc_datetime)
    field(:total, :integer, default: 0)
    field(:total_excluding_tax, :integer, default: 0)
    field(:tax, :integer, default: 0)
    field(:amount_paid, :integer, default: 0)
    field(:credit_applied, :integer, default: 0)
    field(:paid_out_of_band, :boolean, default: false)
    field(:synced_at, :utc_datetime)

    belongs_to(:user, Sanbase.Accounts.User)
    has_many(:lines, Sanbase.Billing.InvoiceMirror.InvoiceLine)

    timestamps(type: :utc_datetime)
  end

  @fields ~w(stripe_invoice_id invoice_number stripe_customer_id user_id customer_email
             stripe_subscription_id status billing_reason currency invoiced_at paid_at total
             total_excluding_tax tax amount_paid credit_applied paid_out_of_band synced_at)a

  def changeset(invoice, attrs) do
    invoice
    |> cast(attrs, @fields)
    |> validate_required([:stripe_invoice_id, :invoiced_at, :synced_at])
    |> unique_constraint(:stripe_invoice_id)
  end
end
