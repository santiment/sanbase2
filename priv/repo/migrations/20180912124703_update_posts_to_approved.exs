defmodule Sanbase.Repo.Migrations.UpdatePostsToApproved do
  @moduledoc false
  use Ecto.Migration

  alias Sanbase.Insight.Post
  alias Sanbase.Repo

  def up do
    Repo.update_all(Post, set: [state: Post.approved_state()])
  end

  def down do
    Repo.update_all(Post, set: [state: nil])
  end
end
