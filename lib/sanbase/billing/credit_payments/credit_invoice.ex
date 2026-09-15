defmodule Sanbase.Billing.CreditPayments.CreditInvoice do
  @moduledoc ~s"""
  An invoice that Stripe settled from the customer's credit balance, mirrored locally.

  `credit_applied`, `total` and `amount_paid` are in cents, as Stripe reports them.
  `source` and `source_note` are derived - the note is copied from the balance
  adjustment that funded the invoice - so re-running the sync after the classification
  changes rewrites them in place.
  """

  use Ecto.Schema

  import Ecto.Changeset

  schema "stripe_credit_invoices" do
    field(:stripe_invoice_id, :string)
    field(:invoice_number, :string)
    field(:stripe_customer_id, :string)
    field(:customer_email, :string)
    field(:invoiced_at, :utc_datetime)
    field(:status, :string)
    field(:total, :integer, default: 0)
    field(:amount_paid, :integer, default: 0)
    field(:credit_applied, :integer, default: 0)
    field(:paid_out_of_band, :boolean, default: false)
    field(:hosted_invoice_url, :string)
    field(:invoice_pdf, :string)
    field(:source, :string)
    field(:source_note, :string)
    field(:funding_transaction_id, :string)
    field(:synced_at, :utc_datetime)

    belongs_to(:user, Sanbase.Accounts.User)

    timestamps(type: :utc_datetime)
  end

  @fields ~w(stripe_invoice_id invoice_number stripe_customer_id customer_email invoiced_at
             status total amount_paid credit_applied paid_out_of_band hosted_invoice_url
             invoice_pdf source source_note funding_transaction_id synced_at user_id)a

  def changeset(invoice, attrs) do
    invoice
    |> cast(attrs, @fields)
    |> validate_required([:stripe_invoice_id, :invoiced_at, :synced_at])
    |> unique_constraint(:stripe_invoice_id)
  end
end
