defmodule Sanbase.Repo.Migrations.CryptocompareExporterProgress do
  use Ecto.Migration

  def change do
    create table(:cryptocompare_exporter_progress) do
      add(:key, :string, null: false)
      add(:queue, :string, null: false)
      add(:min_timestamp, :integer, null: false)
      add(:max_timestamp, :integer, null: false)

      timestamps()
    end

    create(unique_index(:cryptocompare_exporter_progress, [:key, :queue]))
  end
end
