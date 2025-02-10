defmodule Sanbase.Repo.Migrations.DeleteFromPriceMigrationTmpTable2 do
  @moduledoc false
  use Ecto.Migration

  def up do
    setup()
    Sanbase.Repo.delete_all(Sanbase.PriceMigrationTmp)
  end

  def down do
    :ok
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
  end
end
