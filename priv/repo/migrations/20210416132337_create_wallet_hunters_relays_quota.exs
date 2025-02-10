defmodule Sanbase.Repo.Migrations.CreateWalletHuntersRelaysQuota do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:wallet_hunters_relays_quota) do
      add(:proposals_used, :integer)
      add(:user_id, references(:users, on_delete: :delete_all))

      timestamps()
    end

    create(index(:wallet_hunters_relays_quota, [:user_id]))
  end
end
