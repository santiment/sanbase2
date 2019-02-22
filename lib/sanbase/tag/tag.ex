defmodule Sanbase.Tag do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias __MODULE__
  alias Sanbase.Voting.Post
  alias Sanbase.Signals.UserTrigger

  schema "tags" do
    field(:name, :string)

    many_to_many(:posts, Post, join_through: "posts_tags")
    many_to_many(:user_triggers, UserTrigger, join_through: "user_triggers_tags")
  end

  def changeset(%Tag{} = tag, attrs \\ %{}) do
    tag
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> unique_constraint(:name, name: :tags_name_index)
  end

  @doc ~s"""
  Given a changeset and a map of params, containing `tags`. The tags are added with
  `put_assoc` that works on the whole list of tags.
  """
  @spec put_tags(Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def put_tags(%Ecto.Changeset{} = changeset, %{tags: tags}) do
    params =
      tags
      |> Enum.map(fn tag -> %{name: tag} end)

    Sanbase.Repo.insert_all(Tag, params, on_conflict: :nothing)

    tags =
      from(t in __MODULE__, where: t.name in ^tags)
      |> Sanbase.Repo.all()

    changeset
    |> put_assoc(:tags, tags)
  end

  def put_tags(%Ecto.Changeset{} = changeset, _), do: changeset
end
