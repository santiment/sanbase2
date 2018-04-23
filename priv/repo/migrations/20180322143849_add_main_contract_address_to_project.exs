defmodule Sanbase.Repo.Migrations.AddMainContractAddressToProject do
  use Ecto.Migration

  def change do
    alter table(:project) do
      add(:main_contract_address, :string)
    end
  end
end
