defmodule Sanbase.Repo.Migrations.UpdatePostsToApproved do
  use Ecto.Migration

  alias Sanbase.Repo
  alias Sanbase.Voting.Post

  def up do
    Post |> Repo.update_all(set: [state: Post.approved_state()])
  end

  def down do
    Post |> Repo.update_all(set: [state: nil])
  end
end
