defmodule Sanbase.Repo.Migrations.AddDiscountToStripeInvoiceLines do
  use Ecto.Migration

  # Stripe's line `amount_excluding_tax` is before discounts; the discounts allocated
  # to the line come separately. Revenue is counted from the difference.
  def change do
    alter table(:stripe_invoice_lines) do
      add(:discount, :integer, null: false, default: 0)
    end
  end
end
