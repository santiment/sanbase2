defmodule Sanbase.Repo.Migrations.AddTableConfigurationToWatchlist do
  use Ecto.Migration

  def change do
    alter table("user_lists") do
      add(:table_configuration_id, references(:table_configurations))
    end
  end
end
