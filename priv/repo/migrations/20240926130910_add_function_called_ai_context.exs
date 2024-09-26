defmodule Sanbase.Repo.Migrations.AddFunctionCalledAiContext do
  use Ecto.Migration

  def change do
    alter table(:ai_context) do
      add(:function_called, :string)
    end
  end
end
