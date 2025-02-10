defmodule Sanbase.Repo.Migrations.AddHideProjectOption do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:project) do
      add(:is_hidden, :boolean, default: false)
    end
  end
end
