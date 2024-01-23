defmodule Sanbase.Repo.Migrations.AddUniqueConstraintToIpAddress do
  use Ecto.Migration

  def up do
    alter table(:geoip_data) do
      modify(:ip_address, :string, unique: true)
    end
  end

  def down do
    alter table(:geoip_data) do
      modify(:ip_address, :string, unique: false)
    end
  end
end
