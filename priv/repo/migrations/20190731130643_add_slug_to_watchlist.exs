defmodule Sanbase.Repo.Migrations.AddSlugToWatchlist do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:user_lists) do
      add(:slug, :string, null: true)
    end

    # Nullable unique index
    create(unique_index(:user_lists, :slug))
  end
end
