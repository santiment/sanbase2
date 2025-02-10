defmodule Sanbase.Repo.Migrations.AddUniqueConstraintToIpAddress do
  @moduledoc false
  use Ecto.Migration

  def up do
    drop(index(:geoip_data, [:ip_address]))
    create(unique_index(:geoip_data, [:ip_address]))
  end

  def down do
    drop(index(:geoip_data, [:ip_address]))
    create(index(:geoip_data, [:ip_address]))
  end
end
