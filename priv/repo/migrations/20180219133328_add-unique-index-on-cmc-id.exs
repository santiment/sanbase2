defmodule :"Elixir.Sanbase.Repo.Migrations.Add-unique-index-on-cmc-id" do
  use Ecto.Migration

  def change do
    drop(unique_index("project", [:name]))
    create(unique_index("project", [:coinmarketcap_id]))
  end
end
