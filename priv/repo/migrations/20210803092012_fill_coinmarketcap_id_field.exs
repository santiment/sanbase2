defmodule Sanbase.Repo.Migrations.FillCoinmarketcapIdField do
  use Ecto.Migration

  def up do
    Sanbase.Project.Jobs.fill_coinmarketcap_id()
  end

  def down do
    :ok
  end
end
