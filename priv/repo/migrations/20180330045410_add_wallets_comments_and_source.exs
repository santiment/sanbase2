defmodule Sanbase.Repo.Migrations.AddWalletsCommentsAndSource do
  use Ecto.Migration

  def change do
    alter table(:project_eth_address) do
      add(:source, :text)
      add(:comments, :text)
    end

    alter table(:project_btc_address) do
      add(:source, :text)
      add(:comments, :text)
    end

    alter table(:exchange_eth_addresses) do
      add(:source, :text)
    end
  end
end
