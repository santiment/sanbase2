defmodule Sanbase.Repo.Migrations.AddProposedAddressAndLabelsWalletHunters do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:wallet_hunters_proposals) do
      add(:proposed_address, :string)
      add(:user_labels, {:array, :string}, default: [])
    end
  end
end
