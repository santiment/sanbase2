defmodule Sanbase.Repo.Migrations.AddPostIdIndexes do
  @moduledoc false
  use Ecto.Migration

  def up do
    create(index(:post_images, [:post_id]))
    create(index(:posts_tags, [:post_id]))
    create(index(:posts_metrics, [:post_id]))
    create(index(:votes, [:post_id]))
    create(index(:timeline_events, [:post_id]))
  end

  def down do
    drop(index(:post_images, [:post_id]))
    drop(index(:posts_tags, [:post_id]))
    drop(index(:posts_metrics, [:post_id]))
    drop(index(:votes, [:post_id]))
    drop(index(:timeline_events, [:post_id]))
  end
end
