defmodule Sanbase.Repo.Migrations.CreateInvoiceArchives do
  use Ecto.Migration

  def change do
    create table(:invoice_archives) do
      add(:year, :integer, null: false)
      add(:month, :integer, null: false)
      add(:status, :string, null: false, default: "pending")
      add(:s3_key, :string)
      add(:invoice_count, :integer, default: 0)
      add(:total_amount, :integer, default: 0)
      add(:file_size, :integer)
      add(:error_message, :string)
      add(:generated_by, references(:users, on_delete: :nilify_all))

      timestamps()
    end

    create(unique_index(:invoice_archives, [:year, :month]))
  end
end
