defmodule Sanbase.Tag do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias __MODULE__
  alias Sanbase.Alert.UserTrigger
  alias Sanbase.Insight.Post
  alias Sanbase.Repo

  @posts_join_through_table "posts_tags"
  @user_triggers_join_through_table "user_triggers_tags"
  schema "tags" do
    field(:name, :string)

    many_to_many(:posts, Post, join_through: @posts_join_through_table)
    many_to_many(:user_triggers, UserTrigger, join_through: @user_triggers_join_through_table)
  end

  def changeset(%Tag{} = tag, attrs \\ %{}) do
    tag
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> unique_constraint(:name, name: :tags_name_index)
  end

  def by_names(names) when is_list(names) do
    Repo.all(from(t in __MODULE__, where: t.name in ^names))
  end

  def all, do: Repo.all(__MODULE__)

  @doc ~s"""
  Given a changeset and a map of params, containing `tags`. The tags are added with
  `put_assoc` that works on the whole list of tags.
  """
  @spec put_tags(Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def put_tags(%Ecto.Changeset{} = changeset, %{tags: tags}) when is_list(tags) and length(tags) > 10 do
    Ecto.Changeset.add_error(changeset, :tags, "Cannot add more than 10 tags for a record")
  end

  def put_tags(%Ecto.Changeset{} = changeset, %{tags: tags}) when is_list(tags) do
    tags =
      tags
      |> Enum.filter(&is_binary/1)
      |> Enum.map(fn tag -> %{name: tag} end)

    Repo.insert_all(__MODULE__, tags, on_conflict: :nothing, conflict_target: [:name])

    tag_names = Enum.map(tags, & &1.name)
    tag_structures = by_names(tag_names)

    # The `by_names` functions can return the tags in a different order if any new
    # tags were inserted. Sort the tags in their original order before passing them
    # to put_assoc
    tags =
      Enum.map(tag_names, fn name -> Enum.find(tag_structures, &(&1.name == name)) end)

    put_assoc(changeset, :tags, tags)
  end

  def put_tags(%Ecto.Changeset{} = changeset, _), do: changeset

  def drop_tags(%Post{id: id}) do
    Repo.delete_all(from(pt in @posts_join_through_table, where: pt.post_id == ^id))
  end

  def drop_tags(%UserTrigger{id: id}) do
    Repo.delete_all(from(pt in @user_triggers_join_through_table, where: pt.user_trigger_id == ^id))
  end
end
