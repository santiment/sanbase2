defmodule Sanbase.Repo.Migrations.AddSanBurnCreditTransactions do
  use Ecto.Migration

  def change do
    create table(:san_burn_credit_transactions) do
      add(:address, :string)
      add(:trx_hash, :string)
      add(:san_amount, :float)
      add(:san_price, :float)
      add(:credit_amount, :float)
      add(:trx_datetime, :utc_datetime)
      add(:user_id, references(:users), on_delete: :delete_all)

      timestamps()
    end

    create(index(:san_burn_credit_transactions, :trx_hash))
  end
end
