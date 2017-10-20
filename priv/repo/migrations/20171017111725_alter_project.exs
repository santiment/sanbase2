defmodule Sanbase.Repo.Migrations.AlterProject do
  use Ecto.Migration

  def change do
    alter table(:project) do
      add :market_segment_id, references(:market_segments)
      add :infrastructure_id, references(:infrastructures)
      add :geolocation_country_id, references(:countries)
      add :geolocation_city, :string
      add :website_link, :string
      add :open_source, :boolean
    end

    create index(:project, [:market_segment_id])
    create index(:project, [:infrastructure_id])
    create index(:project, [:geolocation_country_id])
  end
end
