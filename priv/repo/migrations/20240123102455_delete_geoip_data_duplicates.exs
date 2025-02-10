defmodule Sanbase.Repo.Migrations.DeleteGeoipDataDuplicates do
  @moduledoc false
  use Ecto.Migration

  def up do
    setup()

    execute("""
    DELETE FROM geoip_data
    WHERE id NOT IN (
      SELECT MAX(id)
      FROM geoip_data
      GROUP BY ip_address
    )
    """)
  end

  def down do
    :ok
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
  end
end
