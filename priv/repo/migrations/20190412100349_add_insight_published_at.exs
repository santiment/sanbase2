defmodule Sanbase.Repo.Migrations.AddInsightPublishedAt do
  use Ecto.Migration

  import Ecto.Query
  alias Sanbase.Repo
  alias Sanbase.Insight.Post

  def change() do
    alter table(:posts) do
      add(:published_at, :naive_datetime)
    end
  end
end
