defmodule Sanbase.Repo.Migrations.RemovePollAssocFromInsights do
  @moduledoc false
  use Ecto.Migration

  def up do
    alter table(:posts) do
      remove(:poll_id)
    end
  end

  def down do
    alter table(:posts) do
      add(:poll_id, references(:polls, on_delete: :delete_all), null: false)
    end
  end
end
