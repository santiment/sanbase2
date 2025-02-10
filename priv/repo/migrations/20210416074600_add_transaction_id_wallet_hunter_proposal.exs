defmodule Sanbase.Repo.Migrations.AddTransactionIdWalletHunterProposal do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:wallet_hunters_proposals) do
      add(:transaction_id, :string, null: false)
    end

    create(unique_index(:wallet_hunters_proposals, [:transaction_id]))
  end
end
