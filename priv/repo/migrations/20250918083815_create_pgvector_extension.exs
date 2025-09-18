defmodule Sanbase.Repo.Migrations.CreatePgvectorExtension do
  use Ecto.Migration

  def up do
    # The extension is created on stage/prod with the superuser.
    # If it was not, this would fail with insufficient permissions.
    # Creating a migration so it is recorded that this was done, even though
    # it was not done with this migration exactly
    execute("""
    CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA #{schema()};
    """)
  end

  def down do
    execute("""
    DROP EXTENSION IF EXISTS vector;
    """)
  end

  def schema() do
    if Application.get_env(:sanbase, :env) == :dev do
      "public"
    else
      "extensions"
    end
  end
end
