defmodule Sanbase.Repo.Migrations.RemoveProjectTransparencyFromAddresses do
  use Ecto.Migration

  def change do
    alter table(:project_eth_address) do
      remove(:project_transparency)
    end

    alter table(:project_btc_address) do
      remove(:project_transparency)
    end
  end
end
