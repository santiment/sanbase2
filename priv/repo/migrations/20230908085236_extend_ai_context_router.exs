defmodule Sanbase.Repo.Migrations.ExtendAiContextRouter do
  use Ecto.Migration

  def change do
    alter(table(:ai_context)) do
      add(:route, :map, default: %{})
    end
  end
end
