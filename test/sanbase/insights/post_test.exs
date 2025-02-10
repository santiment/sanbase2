defmodule Sanbase.Insight.PostTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Insight.Post
  alias Sanbase.Repo

  test "create_changeset creates the post in approved state" do
    post = insert(:post)

    assert post.state == Post.approved_state()
  end

  test "changes the owner to the fallback user" do
    fallback_user = insert(:insights_fallback_user)
    post = insert(:post)

    Post.assign_all_user_insights_to_anonymous(post.user_id)
    updated_post = Repo.get(Post, post.id)

    assert updated_post.user_id == fallback_user.id
  end

  test "create custom tags when creating post" do
    insert(:tag, %{name: "SAN"})
    user = insert(:user)

    tags = ["SAN", "test1", "test2"]

    post =
      %Post{user_id: user.id}
      |> Post.create_changeset(%{title: "test title", tags: tags})
      |> Repo.insert!()

    assert Enum.map(post.tags, & &1.name) == tags
  end
end
