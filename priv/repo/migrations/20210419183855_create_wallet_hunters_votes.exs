defmodule Sanbase.Repo.Migrations.CreateWalletHuntersVotes do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:wallet_hunters_votes) do
      add(:proposal_id, :integer)
      add(:transaction_id, :string)
      add(:transaction_status, :string, default: "pending")
      add(:user_id, references(:users, on_delete: :delete_all))

      timestamps()
    end

    create(index(:wallet_hunters_votes, [:user_id]))
  end
end
