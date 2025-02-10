defmodule Sanbase.Repo.Migrations.AddNameToUsers do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:name, :string, null: true)
    end
  end
end
