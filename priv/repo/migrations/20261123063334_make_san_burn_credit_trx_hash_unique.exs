defmodule Sanbase.Repo.Migrations.MakeSanBurnCreditTrxHashUnique do
  use Ecto.Migration

  def up() do
    alter table(:san_burn_credit_transactions) do
      add(:status, :string, null: false, default: "credited")
      add(:stripe_credit_id, :string)
    end

    execute("""
    DELETE FROM san_burn_credit_transactions a
    USING san_burn_credit_transactions b
    WHERE a.trx_hash = b.trx_hash
      AND a.id > b.id
    """)

    drop(index(:san_burn_credit_transactions, [:trx_hash]))
    create(unique_index(:san_burn_credit_transactions, [:trx_hash]))
  end

  def down() do
    drop(unique_index(:san_burn_credit_transactions, [:trx_hash]))
    create(index(:san_burn_credit_transactions, [:trx_hash]))

    alter table(:san_burn_credit_transactions) do
      remove(:stripe_credit_id)
      remove(:status)
    end
  end
end
