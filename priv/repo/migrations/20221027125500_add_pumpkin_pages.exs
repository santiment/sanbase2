defmodule Sanbase.Repo.Migrations.AddPumpkinPages do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:pumpkins) do
      add(:pages, {:array, :string}, default: [])
    end
  end
end
