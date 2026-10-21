defmodule Sanbase.Billing.InvoiceMirror.InvoiceLine do
  @moduledoc ~s"""
  One line of a mirrored Stripe invoice.

  The line is what says which plan was paid for and for which period, so "was this
  user a business client on this date" and "how much were they paying" are both
  answered from lines. `plan_id` is resolved from the Stripe price id; lines of bundle
  prices and one-off invoice items have no plan.
  """

  use Ecto.Schema

  import Ecto.Changeset

  schema "stripe_invoice_lines" do
    field(:stripe_line_id, :string)
    field(:stripe_price_id, :string)
    field(:description, :string)
    field(:period_start, :utc_datetime)
    field(:period_end, :utc_datetime)
    field(:amount, :integer, default: 0)
    field(:amount_excluding_tax, :integer, default: 0)
    field(:quantity, :integer)
    field(:proration, :boolean, default: false)

    belongs_to(:invoice, Sanbase.Billing.InvoiceMirror.Invoice)
    belongs_to(:plan, Sanbase.Billing.Plan)

    timestamps(type: :utc_datetime)
  end

  @fields ~w(invoice_id stripe_line_id stripe_price_id plan_id description period_start
             period_end amount amount_excluding_tax quantity proration)a

  def changeset(line, attrs) do
    line
    |> cast(attrs, @fields)
    |> validate_required([:invoice_id, :stripe_line_id])
    |> unique_constraint([:invoice_id, :stripe_line_id])
  end
end
