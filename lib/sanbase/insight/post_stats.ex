defmodule Sanbase.Insight.Post.Stats do
  @moduledoc false
  import Ecto.Query

  alias Sanbase.Comment.PostComment
  alias Sanbase.Insight.Post
  alias Sanbase.Repo

  def post_id_to_comments_count do
    from(
      pc in PostComment,
      select: {pc.post_id, count(pc.comment_id)},
      group_by: pc.post_id
    )
    |> Repo.all()
    |> Map.new()
  end

  def user_id_to_post_ids do
    from(
      p in Post,
      select: {p.user_id, fragment("array_agg(?)", p.id)},
      group_by: p.user_id
    )
    |> Repo.all()
    |> Map.new()
  end
end
