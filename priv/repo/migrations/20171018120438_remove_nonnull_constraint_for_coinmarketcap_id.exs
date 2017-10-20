defmodule Sanbase.Repo.Migrations.RemoveNonnullConstraintForCoinmarketcapId do
  use Ecto.Migration

  def up do
    alter table("project") do
      modify :coinmarketcap_id, :string, null: true
    end
  end

  def down do
    alter table("project") do
      modify :coinmarketcap_id, :text, null: false
    end
  end

end
