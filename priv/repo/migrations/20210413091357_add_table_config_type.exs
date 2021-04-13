defmodule Sanbase.Repo.Migrations.AddTableConfigType do
  use Ecto.Migration

  def up do
    TableConfigurationType.create_type()

    alter table(:table_configurations) do
      add(:type, :table_configuration_type)
    end
  end

  def down do
    TableConfigurationType.drop_type()
  end
end
