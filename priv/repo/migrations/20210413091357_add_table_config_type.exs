defmodule Sanbase.Repo.Migrations.AddTableConfigType do
  @moduledoc false
  use Ecto.Migration

  def up do
    execute("""
    DO $$ BEGIN
      CREATE TYPE public.table_configuration_type AS ENUM ('project', 'blockchain_address');
    EXCEPTION
      WHEN duplicate_object THEN null;
    END $$;
    """)

    alter table(:table_configurations) do
      add(:type, :table_configuration_type)
    end
  end

  def down do
    alter table(:table_configurations) do
      remove(:type)
    end

    TableConfigurationType.drop_type()
  end
end
