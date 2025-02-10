defmodule Sanbase.Repo.Migrations.AddIsSuperuserFieldInUser do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:is_superuser, :boolean, default: false)
    end
  end
end
