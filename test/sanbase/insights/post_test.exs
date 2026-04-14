defmodule Sanbase.Insight.PostTest do
  use Sanbase.DataCase, async: true

  import Sanbase.Factory
  alias Sanbase.Repo
  alias Sanbase.Insight.{Post, PostImage}

  test "create_changeset creates the post in approved state" do
    post = insert(:post)

    assert post.state == Post.approved_state()
  end

  test "publish insight by santiment user auto-approves the post" do
    user = insert(:user, email: "author@santiment.net")

    post =
      insert(:post, user: user, ready_state: Post.draft(), state: Post.awaiting_approval_state())

    assert {:ok, %Post{} = published_post} = Post.publish(post.id, user.id)
    assert published_post.state == Post.approved_state()
    assert published_post.ready_state == Post.published()
  end

  test "publish insight by gmail user awaits approval" do
    user = insert(:user, email: "author@gmail.com")

    post =
      insert(:post, user: user, ready_state: Post.draft(), state: Post.awaiting_approval_state())

    assert {:ok, %Post{} = published_post} = Post.publish(post.id, user.id)
    assert published_post.state == Post.awaiting_approval_state()
    assert published_post.ready_state == Post.published()
  end

  test "changes the owner to the fallback user" do
    fallback_user = insert(:insights_fallback_user)
    post = insert(:post)

    Post.assign_all_user_insights_to_anonymous(post.user_id)
    updated_post = Post |> Repo.get(post.id)

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

  test "update replaces post images when text references change" do
    user = insert(:user)

    storage_dir = Application.get_env(:waffle, :storage_dir)

    storage_dir =
      if String.ends_with?(storage_dir, "/"), do: storage_dir, else: storage_dir <> "/"

    old_image_url = storage_dir <> "image-old.png"
    new_image_url = storage_dir <> "image-new.png"

    post =
      insert(:post,
        user: user,
        text: "Post text #{old_image_url}"
      )

    post_id = post.id

    old_image =
      PostImage.create!(%{
        post_id: post.id,
        file_name: "image-old.png",
        image_url: old_image_url,
        content_hash: "hash-old",
        hash_algorithm: "sha256"
      })

    new_image =
      PostImage.create!(%{
        file_name: "image-new.png",
        image_url: new_image_url,
        content_hash: "hash-new",
        hash_algorithm: "sha256"
      })

    assert {:ok, %Post{id: ^post_id}} =
             Post.update(post_id, user, %{text: "Updated text #{new_image_url}"})

    updated_post =
      Post
      |> Repo.get!(post_id)
      |> Repo.preload(:images)

    assert [image] = updated_post.images
    assert image.id == new_image.id
    assert Repo.get!(PostImage, new_image.id).post_id == post.id
    # Old image is unlinked (post_id set to NULL), not deleted
    old_image_record = Repo.get(PostImage, old_image.id)
    assert old_image_record
    assert is_nil(old_image_record.post_id)
  end
end
