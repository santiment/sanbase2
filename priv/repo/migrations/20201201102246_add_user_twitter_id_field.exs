defmodule Sanbase.Repo.Migrations.AddUserTwitterIdField do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:twitter_id, :string, default: nil, null: true)
    end

    create(unique_index(:users, [:twitter_id]))
  end
end
