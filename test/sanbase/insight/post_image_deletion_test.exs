defmodule Sanbase.Insight.PostImageDeletionTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import Mock

  alias Sanbase.Insight.Post
  alias Sanbase.Insight.PostImage
  alias Sanbase.Repo

  setup do
    user = insert(:user)
    other_user = insert(:user)

    {:ok, user: user, other_user: other_user}
  end

  defp create_image(user, opts) do
    post_id = Keyword.get(opts, :post_id)

    image_url =
      Keyword.get(
        opts,
        :image_url,
        "/tmp/sanbase/filestore-test/#{System.unique_integer([:positive])}_image.png"
      )

    PostImage.create!(%{
      user_id: user.id,
      post_id: post_id,
      file_name: "test_image.png",
      image_url: image_url,
      content_hash: "hash_#{System.unique_integer([:positive])}",
      hash_algorithm: "sha256"
    })
  end

  describe "delete_post_images/1" do
    test "deletes S3 file when owner uploaded the image and it's not used elsewhere", %{
      user: user
    } do
      post = insert(:post, user: user, text: "some text")

      image =
        create_image(user,
          post_id: post.id,
          image_url: "/tmp/sanbase/filestore-test/owner_image.png"
        )

      with_mock Sanbase.FileStore, [:passthrough], delete: fn _url -> :ok end do
        Post.delete_post_images(post)

        assert called(Sanbase.FileStore.delete(image.image_url))
      end
    end

    test "does NOT delete S3 file when image was uploaded by different user", %{
      user: user,
      other_user: other_user
    } do
      post = insert(:post, user: user, text: "some text")

      image =
        create_image(other_user,
          post_id: post.id,
          image_url: "/tmp/sanbase/filestore-test/other_image.png"
        )

      with_mock Sanbase.FileStore, [:passthrough], delete: fn _url -> :ok end do
        Post.delete_post_images(post)

        refute called(Sanbase.FileStore.delete(image.image_url))
      end
    end

    test "does NOT delete S3 file when image URL appears in another post's text", %{user: user} do
      image_url = "/tmp/sanbase/filestore-test/shared_image.png"
      post = insert(:post, user: user, text: "some text")
      _other_post = insert(:post, user: user, text: "uses the image #{image_url} here")
      _image = create_image(user, post_id: post.id, image_url: image_url)

      with_mock Sanbase.FileStore, [:passthrough], delete: fn _url -> :ok end do
        Post.delete_post_images(post)

        refute called(Sanbase.FileStore.delete(image_url))
      end
    end

    test "deletes S3 file when image is owned and not referenced in other posts", %{user: user} do
      image_url = "/tmp/sanbase/filestore-test/unique_image.png"
      post = insert(:post, user: user, text: "my post with #{image_url}")
      _image = create_image(user, post_id: post.id, image_url: image_url)

      with_mock Sanbase.FileStore, [:passthrough], delete: fn _url -> :ok end do
        Post.delete_post_images(post)

        assert called(Sanbase.FileStore.delete(image_url))
      end
    end

    test "handles post with no images", %{user: user} do
      post = insert(:post, user: user, text: "no images here")

      # Should not raise
      assert Post.delete_post_images(post) == :ok
    end
  end

  describe "auto_link_images/1" do
    test "links unlinked images matching URLs in text", %{user: user} do
      image_url = "/tmp/sanbase/filestore-test/auto_link_test.png"
      image = create_image(user, image_url: image_url)

      post = insert(:post, user: user, text: "Check out #{image_url} in this post")

      Post.auto_link_images(post)

      updated_image = Repo.get(PostImage, image.id)
      assert updated_image.post_id == post.id
    end

    test "does not link images uploaded by a different user", %{
      user: user,
      other_user: other_user
    } do
      image_url = "/tmp/sanbase/filestore-test/other_user_image.png"
      image = create_image(other_user, image_url: image_url)

      post = insert(:post, user: user, text: "Using #{image_url}")

      Post.auto_link_images(post)

      updated_image = Repo.get(PostImage, image.id)
      assert updated_image.post_id == nil
    end

    test "does not link images already linked to a different post", %{user: user} do
      image_url = "/tmp/sanbase/filestore-test/already_linked.png"
      other_post = insert(:post, user: user, text: "first post")
      image = create_image(user, post_id: other_post.id, image_url: image_url)

      new_post = insert(:post, user: user, text: "Using #{image_url} too")

      Post.auto_link_images(new_post)

      updated_image = Repo.get(PostImage, image.id)
      # Should remain linked to the original post
      assert updated_image.post_id == other_post.id
    end

    test "handles post with nil text", %{user: user} do
      post = %Post{id: 1, user_id: user.id, text: nil}
      assert Post.auto_link_images(post) == :ok
    end
  end
end
