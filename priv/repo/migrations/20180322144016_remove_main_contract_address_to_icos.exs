defmodule Sanbase.Repo.Migrations.RemoveMainContractAddressToIcos do
  use Ecto.Migration

  def change do
    alter table(:icos) do
      remove(:main_contract_address)
    end
  end
end
