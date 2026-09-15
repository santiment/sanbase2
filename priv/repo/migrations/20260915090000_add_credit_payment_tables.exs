defmodule Sanbase.Repo.Migrations.AddCreditPaymentTables do
  use Ecto.Migration

  @moduledoc """
  Local mirror of the invoices settled from a Stripe credit balance - crypto and wire
  payments - plus the balance ledger entries that carry the payment reference.

  Stripe is still the source of truth. These tables exist so the admin panel and any
  revenue report can read months of history without paginating the Stripe API on every
  page load, and so a fixed classification can be backfilled over what was already
  imported.
  """

  def change do
    create table(:stripe_credit_invoices) do
      add(:stripe_invoice_id, :string, null: false)
      add(:invoice_number, :string)
      add(:stripe_customer_id, :string)
      add(:user_id, references(:users, on_delete: :nilify_all))
      add(:customer_email, :string)
      add(:invoiced_at, :utc_datetime, null: false)
      add(:status, :string)
      add(:total, :integer, null: false, default: 0)
      add(:amount_paid, :integer, null: false, default: 0)
      add(:credit_applied, :integer, null: false, default: 0)
      add(:paid_out_of_band, :boolean, null: false, default: false)
      add(:hosted_invoice_url, :text)
      add(:invoice_pdf, :text)
      add(:source, :string)
      add(:source_note, :text)
      add(:funding_transaction_id, :string)
      add(:synced_at, :utc_datetime, null: false)

      timestamps()
    end

    create(unique_index(:stripe_credit_invoices, [:stripe_invoice_id]))
    create(index(:stripe_credit_invoices, [:invoiced_at]))
    create(index(:stripe_credit_invoices, [:stripe_customer_id]))
    create(index(:stripe_credit_invoices, [:source]))

    create table(:stripe_credit_balance_transactions) do
      add(:stripe_transaction_id, :string, null: false)
      add(:stripe_customer_id, :string, null: false)
      add(:user_id, references(:users, on_delete: :nilify_all))
      add(:granted_at, :utc_datetime, null: false)
      # Stripe's own sign: a negative amount credits the customer, which is money in.
      add(:amount, :integer, null: false, default: 0)
      add(:type, :string)
      add(:description, :text)
      add(:stripe_invoice_id, :string)
      add(:source, :string)
      add(:synced_at, :utc_datetime, null: false)

      timestamps()
    end

    create(unique_index(:stripe_credit_balance_transactions, [:stripe_transaction_id]))
    create(index(:stripe_credit_balance_transactions, [:granted_at]))
    create(index(:stripe_credit_balance_transactions, [:stripe_customer_id]))

    # Which ranges have actually been imported, so a gap in the data is visible instead
    # of being mistaken for a month with no credit payments.
    create table(:stripe_credit_sync_runs) do
      add(:from_date, :date, null: false)
      add(:to_date, :date, null: false)
      add(:status, :string, null: false, default: "running")
      add(:invoices_upserted, :integer, null: false, default: 0)
      add(:grants_upserted, :integer, null: false, default: 0)
      add(:customers_scanned, :integer, null: false, default: 0)
      add(:duration_ms, :integer)
      add(:error_message, :text)
      add(:triggered_by, references(:users, on_delete: :nilify_all))

      timestamps()
    end

    create(index(:stripe_credit_sync_runs, [:inserted_at]))
  end
end
