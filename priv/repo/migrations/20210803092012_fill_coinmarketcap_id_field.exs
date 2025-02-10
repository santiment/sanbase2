defmodule Sanbase.Repo.Migrations.FillCoinmarketcapIdField do
  @moduledoc false
  use Ecto.Migration

  def up do
    Sanbase.Project.Jobs.fill_coinmarketcap_id()
  end

  def down do
    :ok
  end
end
