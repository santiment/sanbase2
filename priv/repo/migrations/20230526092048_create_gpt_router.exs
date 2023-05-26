defmodule Sanbase.Repo.Migrations.CreateGptRouter do
  use Ecto.Migration

  def change do
    create table(:gpt_router) do
      add(:question, :text)
      add(:route, :string)
      add(:scores, :jsonb, default: "{}")
      add(:error, :text)
      add(:elapsed_time, :integer)

      timestamps()
    end
  end
end
