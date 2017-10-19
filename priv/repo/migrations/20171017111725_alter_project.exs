defmodule Sanbase.Repo.Migrations.AlterProject do
  use Ecto.Migration

  def change do
    alter table(:project) do
      add :market_segment_id, references(:market_segments)
      add :infrastructure_code, references(:infrastructures)
      add :geolocation_country_code, references(:countries)
      add :geolocation_city, :text
      add :website_link, :text
      add :open_source, :boolean
    end

    create index(:project, [:market_segment_id])
    create index(:project, [:infrastructure_code])
    create index(:project, [:geolocation_country_code])
  end
end
