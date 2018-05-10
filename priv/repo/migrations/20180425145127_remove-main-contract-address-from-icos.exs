defmodule :"Elixir.Sanbase.Repo.Migrations.Remove-main-contract-address-from-icos" do
  use Ecto.Migration

  def change do
    alter table(:icos) do
      remove(:main_contract_address)
    end
  end
end
