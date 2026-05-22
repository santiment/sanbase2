defmodule Sanbase.Repo.Migrations.AddAreActivityTracesHiddenToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:are_activity_traces_hidden, :boolean, null: false, default: false)
    end

    create(
      index(:users, [:are_activity_traces_hidden], where: "are_activity_traces_hidden = true")
    )
  end
end
