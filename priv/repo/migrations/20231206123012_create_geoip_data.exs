defmodule Sanbase.Repo.Migrations.CreateGeoipData do
  use Ecto.Migration

  def change do
    create table(:geoip_data) do
      add(:ip_address, :string)
      add(:is_vpn, :boolean)
      add(:country_name, :string)
      add(:country_code, :string)

      timestamps()
    end

    create(index(:geoip_data, [:ip_address]))
  end
end
