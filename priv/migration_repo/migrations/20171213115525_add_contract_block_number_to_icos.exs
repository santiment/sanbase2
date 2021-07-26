defmodule Sanbase.Repo.Migrations.AddContractBlockNumberToIcos do
  use Ecto.Migration

  def change do
    alter table(:icos) do
      add(:contract_block_number, :integer)
    end
  end
end
