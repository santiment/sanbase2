defmodule Sanbase.Repo.Migrations.ExtendProjectsTableHiddenInfo do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:project) do
      add(:hidden_since, :utc_datetime)
      add(:hidden_reason, :text)
    end
  end
end
