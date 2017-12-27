defmodule Sanbase.Repo.Migrations.AddContractAbiToIcos do
  use Ecto.Migration

  def change do
    alter table(:icos) do
      add :contract_abi, :text
    end
  end
end
