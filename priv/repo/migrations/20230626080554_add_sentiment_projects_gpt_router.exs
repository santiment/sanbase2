defmodule Sanbase.Repo.Migrations.AddSentimentProjectsGptRouter do
  use Ecto.Migration

  def change do
    alter table(:gpt_router) do
      add(:sentiment, :boolean, default: false)
      add(:projects, {:array, :string}, default: [])
    end
  end
end
