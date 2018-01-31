defmodule :"Elixir.Sanbase.Repo.Migrations.Add-circulating-supply-and-decimal-points" do
  use Ecto.Migration

  def change do
    alter table(:project) do
      add(:token_decimals, :integer)
      add(:total_supply, :decimal)
    end
  end
end
