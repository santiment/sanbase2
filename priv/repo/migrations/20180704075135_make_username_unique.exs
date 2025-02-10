defmodule Sanbase.Repo.Migrations.MakeUsernameUnique do
  @moduledoc false
  use Ecto.Migration

  def up do
    create(unique_index(:users, [:username]))
  end

  def down do
    drop(index(:users, [:username]))
  end
end
