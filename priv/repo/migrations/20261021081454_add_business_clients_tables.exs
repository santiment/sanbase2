defmodule Sanbase.Repo.Migrations.AddBusinessClientsTables do
  use Ecto.Migration

  @moduledoc """
  Tables behind the Business Clients admin page.

  `stripe_invoices` and `stripe_invoice_lines` mirror every Stripe invoice, not only
  the credit-settled ones in `stripe_credit_invoices`. Card payments are otherwise only
  sent to Kafka, and a subscription row loses its history on a plan change, so revenue,
  churn and renewal are all derived from the invoice lines: each line carries the plan,
  the period it pays for and the amount.

  The `business_client_*` tables hold what only people know - log entries, per-client
  overrides, the editable settings - and the monthly snapshots, so a month's numbers
  stay as they were reported.
  """

  def change do
    create table(:stripe_invoices) do
      add(:stripe_invoice_id, :string, null: false)
      add(:invoice_number, :string)
      add(:stripe_customer_id, :string)
      add(:user_id, references(:users, on_delete: :nilify_all))
      add(:customer_email, :string)
      add(:stripe_subscription_id, :string)
      add(:status, :string)
      add(:billing_reason, :string)
      add(:currency, :string)
      add(:invoiced_at, :utc_datetime, null: false)
      add(:paid_at, :utc_datetime)
      add(:total, :integer, null: false, default: 0)
      add(:total_excluding_tax, :integer, null: false, default: 0)
      add(:tax, :integer, null: false, default: 0)
      add(:amount_paid, :integer, null: false, default: 0)
      add(:credit_applied, :integer, null: false, default: 0)
      add(:paid_out_of_band, :boolean, null: false, default: false)
      add(:synced_at, :utc_datetime, null: false)

      timestamps()
    end

    create(unique_index(:stripe_invoices, [:stripe_invoice_id]))
    create(index(:stripe_invoices, [:invoiced_at]))
    create(index(:stripe_invoices, [:user_id]))
    create(index(:stripe_invoices, [:stripe_customer_id]))

    create table(:stripe_invoice_lines) do
      add(:invoice_id, references(:stripe_invoices, on_delete: :delete_all), null: false)
      add(:stripe_line_id, :string, null: false)
      add(:stripe_price_id, :string)
      add(:plan_id, references(:plans, on_delete: :nilify_all))
      add(:description, :text)
      add(:period_start, :utc_datetime)
      add(:period_end, :utc_datetime)
      add(:amount, :integer, null: false, default: 0)
      add(:amount_excluding_tax, :integer, null: false, default: 0)
      add(:quantity, :integer)
      add(:proration, :boolean, null: false, default: false)

      timestamps()
    end

    create(unique_index(:stripe_invoice_lines, [:invoice_id, :stripe_line_id]))
    create(index(:stripe_invoice_lines, [:plan_id]))
    create(index(:stripe_invoice_lines, [:period_start, :period_end]))

    # Which ranges have been imported, so a gap is visible instead of looking like a
    # month without revenue.
    create table(:stripe_invoice_sync_runs) do
      add(:from_date, :date, null: false)
      add(:to_date, :date, null: false)
      add(:status, :string, null: false, default: "running")
      add(:invoices_upserted, :integer, null: false, default: 0)
      add(:lines_upserted, :integer, null: false, default: 0)
      add(:duration_ms, :integer)
      add(:error_message, :text)
      add(:triggered_by, references(:users, on_delete: :nilify_all))

      timestamps()
    end

    create(index(:stripe_invoice_sync_runs, [:inserted_at]))

    # A single row keyed by `key`, so the editable parameters of every formula live in
    # one place and the page can say which values produced a number.
    create table(:business_client_settings) do
      add(:key, :string, null: false)
      add(:settings, :map, null: false, default: %{})
      add(:updated_by_id, references(:users, on_delete: :nilify_all))

      timestamps()
    end

    create(unique_index(:business_client_settings, [:key]))

    create table(:business_client_log_entries) do
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      add(:type, :string, null: false)
      add(:severity, :string, null: false, default: "none")
      add(:note, :text)
      add(:author_id, references(:users, on_delete: :nilify_all))
      add(:resolved_at, :utc_datetime)
      add(:resolved_by_id, references(:users, on_delete: :nilify_all))

      timestamps()
    end

    create(index(:business_client_log_entries, [:user_id]))
    create(index(:business_client_log_entries, [:resolved_at]))

    # An admin's yes/no on whether a user counts as a business client, for the email
    # domains the free-provider list gets wrong.
    create table(:business_client_overrides) do
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      add(:business, :boolean, null: false)
      add(:note, :text)
      add(:set_by_id, references(:users, on_delete: :nilify_all))

      timestamps()
    end

    create(unique_index(:business_client_overrides, [:user_id]))

    # Append-only: a month's numbers are written once and never rewritten.
    create table(:business_client_snapshots) do
      add(:month, :date, null: false)
      add(:user_id, references(:users, on_delete: :nilify_all))
      add(:data, :map, null: false, default: %{})

      timestamps(updated_at: false)
    end

    create(unique_index(:business_client_snapshots, [:month, :user_id]))

    create table(:business_metrics_snapshots) do
      add(:month, :date, null: false)
      add(:data, :map, null: false, default: %{})

      timestamps(updated_at: false)
    end

    create(unique_index(:business_metrics_snapshots, [:month]))
  end
end
