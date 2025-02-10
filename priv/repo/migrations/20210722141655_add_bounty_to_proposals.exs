defmodule Sanbase.Repo.Migrations.AddBountyToProposals do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:wallet_hunters_proposals) do
      add(:bounty_id, references(:wallet_hunters_bounties, on_delete: :delete_all))
    end
  end
end
