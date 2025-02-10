defmodule Sanbase.Repo.Migrations.CreateWalletHuntersBounties do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:wallet_hunters_bounties) do
      add(:title, :string)
      add(:description, :text)
      add(:duration, :string)
      add(:proposals_count, :integer)
      add(:proposal_reward, :integer)
      add(:transaction_id, :string)
      add(:transaction_status, :string, dafault: "pending")
      add(:hash_digest, :string)
      add(:user_id, references(:users, on_delete: :nothing))

      timestamps()
    end

    create(index(:wallet_hunters_bounties, [:user_id]))
  end
end
