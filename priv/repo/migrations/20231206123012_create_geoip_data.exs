defmodule Sanbase.Repo.Migrations.CreateGeoipData do
  use Ecto.Migration

  def change do
    create table(:geoip_data) do
      add(:ip_address, :string, null: false)
      add(:is_vpn, :boolean, null: false)
      add(:country_name, :string, null: false)
      add(:country_code, :string, null: false)

      timestamps()
    end

    create(index(:geoip_data, [:ip_address]))
  end
end
