defmodule Sanbase.Repo.Migrations.AddTypeToWatchlists do
  @moduledoc false
  use Ecto.Migration

  def up do
    execute("""
    DO $$ BEGIN
      CREATE TYPE public.watchlist_type AS ENUM ('project', 'blockchain_address');
    EXCEPTION
      WHEN duplicate_object THEN null;
    END $$;
    """)

    alter table(:user_lists) do
      add(:type, :watchlist_type, null: false, default: "project")
    end
  end

  def down do
    alter table(:user_lists) do
      remove(:type)
    end

    WatchlistType.drop_type()
  end
end
