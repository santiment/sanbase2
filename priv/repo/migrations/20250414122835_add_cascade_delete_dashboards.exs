defmodule Sanbase.Repo.Migrations.AddCascadeDeleteDashboards do
  use Ecto.Migration

  def up do
    # This materialized view disables the column modification with error
    # ** (Postgrex.Error) ERROR 0A000 (feature_not_supported) cannot alter type of a column used by a view or rule
    # rule _RETURN on materialized view entities depends on column "user_id"
    #
    # Drop the materialized view as it is no longer used and populated -- latest
    # data (as of 2025) is from 2022
    execute("DROP MATERIALIZED VIEW IF EXISTS entities;")

    # Modify dashboards
    drop(constraint(:dashboards, "dashboards_user_id_fkey"))

    alter table(:dashboards) do
      modify(:user_id, references(:users, on_delete: :delete_all))
    end

    # Modify queries

    drop(constraint(:queries, "queries_user_id_fkey"))

    alter table(:queries) do
      modify(:user_id, references(:users, on_delete: :delete_all))
    end
  end

  def down do
    :ok
  end
end
