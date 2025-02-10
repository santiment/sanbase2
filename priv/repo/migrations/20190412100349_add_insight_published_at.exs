defmodule Sanbase.Repo.Migrations.AddInsightPublishedAt do
  @moduledoc false
  use Ecto.Migration

  import Ecto.Query

  alias Sanbase.Insight.Post
  alias Sanbase.Repo

  def change do
    alter table(:posts) do
      add(:published_at, :naive_datetime)
    end
  end
end
