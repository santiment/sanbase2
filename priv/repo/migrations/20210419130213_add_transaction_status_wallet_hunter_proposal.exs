defmodule Sanbase.Repo.Migrations.AddTransactionStatusWalletHunterProposal do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:wallet_hunters_proposals) do
      add(:transaction_status, :string, null: false, default: "pending")
    end
  end
end
