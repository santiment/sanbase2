defmodule Sanbase.Voting.Post do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  use Timex.Ecto.Timestamps

  alias Sanbase.Voting.{Poll, Post, Vote, PostImage, Tag}
  alias Sanbase.Auth.User

  @approved "approved"
  @declined "declined"

  schema "posts" do
    belongs_to(:poll, Poll)
    belongs_to(:user, User)
    has_many(:votes, Vote, on_delete: :delete_all)

    field(:title, :string)
    field(:short_desc, :string)
    field(:link, :string)
    field(:text, :string)
    field(:state, :string)
    field(:moderation_comment, :string)

    has_many(:images, PostImage, on_delete: :delete_all)

    many_to_many(
      :tags,
      Tag,
      join_through: "posts_tags",
      on_replace: :delete,
      on_delete: :delete_all
    )

    timestamps()
  end

  def create_changeset(%Post{} = post, attrs) do
    post
    |> cast(attrs, [:title, :short_desc, :link, :text])
    |> tags_cast(attrs)
    |> images_cast(attrs)
    |> validate_required([:poll_id, :user_id, :title])
    |> validate_length(:title, max: 140)
    |> unique_constraint(:poll_id, name: :posts_poll_id_title_index)
  end

  def approved_state(), do: @approved

  def declined_state(), do: @declined

  # Helper functions
  defp tags_cast(changeset, %{tags: tags}) do
    tags = Tag |> where([t], t.name in ^tags) |> Sanbase.Repo.all()

    changeset
    |> put_assoc(:tags, tags)
  end

  defp tags_cast(changeset, _), do: changeset

  defp images_cast(changeset, %{image_urls: image_urls}) do
    images = PostImage |> where([i], i.image_url in ^image_urls) |> Sanbase.Repo.all()

    if Enum.any?(images, fn %{post_id: post_id} -> not is_nil(post_id) end) do
      changeset
      |> Ecto.Changeset.add_error(
        :images,
        "The images you are trying to use are already used in another post"
      )
    else
      changeset
      |> put_assoc(:images, images)
    end
  end

  defp images_cast(changeset, _), do: changeset
end
