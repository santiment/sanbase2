defmodule Sanbase.Repo.Migrations.AddFieldToVotes do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:votes) do
      add(:count, :integer, default: 1)
    end
  end
end
