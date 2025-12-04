defmodule Sanbase.Repo.Migrations.RemoveContractDefaultDecimals do
  use Ecto.Migration

  def up do
    alter table(:contract_addresses) do
      modify(:decimals, :integer, default: nil)
    end
  end

  def down do
    alter table(:contract_addresses) do
      modify(:decimals, :integer, default: 0)
    end
  end
end
