defmodule Sanbase.Repo.Migrations.CreateWalletHuntersProposals do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:wallet_hunters_proposals) do
      add(:title, :text)
      add(:text, :text)
      add(:proposal_id, :integer)
      add(:hunter_address, :string)
      add(:user_id, references(:users), null: true)

      timestamps()
    end

    create(unique_index(:wallet_hunters_proposals, [:proposal_id]))
  end
end
