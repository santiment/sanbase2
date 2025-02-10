defmodule Sanbase.Repo.Migrations.AddTagsToReports do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:reports) do
      add(:tags, {:array, :string}, default: [])
    end
  end
end
