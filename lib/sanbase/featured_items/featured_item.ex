defmodule Sanbase.FeaturedItem do
  @moduledoc ~s"""
  Module for marking insights, watchlists and user triggers as featured.
  Featured items are meant to be used by the frontend to show them in a special way.
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Insight.Post
  alias Sanbase.UserList
  alias Sanbase.Signals.UserTrigger

  @table "featured_items"
  schema @table do
    belongs_to(:post, Post)
    belongs_to(:user_list, UserList)
    belongs_to(:user_trigger, UserTrigger)

    timestamps()
  end

  @doc ~s"""
  Changeset for the FeaturedItem module.
  There is a database check that exactly one of `post_id`, `user_list_id` and
  `user_trigger_id` fields is set
  """
  def changeset(%__MODULE__{} = featured_items, attrs \\ %{}) do
    featured_items
    |> cast(attrs, [:post_id, :user_list_id, :user_trigger_id])
    |> unique_constraint(:post_id)
    |> unique_constraint(:user_list_id)
    |> unique_constraint(:user_trigger_id)
  end

  def insights() do
    insights_query()
    |> join(:inner, [fi], fi in assoc(fi, :post))
    |> select([_fi, post], post)
    |> Repo.all()
    |> Repo.preload([:user, :poll])
  end

  def watchlists() do
    watchlists_query()
    |> join(:inner, [fi], fi in assoc(fi, :user_list))
    |> select([_fi, user_list], user_list)
    |> Repo.all()
    |> Repo.preload([:user, :list_items])
  end

  def user_triggers() do
    user_triggers_query()
    |> join(:inner, [fi], fi in assoc(fi, :user_trigger))
    |> select([_fi, trigger], trigger)
    |> Repo.all()
    |> Repo.preload([:user, :tags])
  end

  @doc ~s"""
  Mark the insight, watchlist or user trigger as featured or not.

  Update the record for the insight. If it the second argument is `false` any
  present record will be deleted. If the second argument is `true` a new record
  will be created if it does not exist
  """
  @spec update_item(%Post{} | %UserList{} | %UserTrigger{}, boolean) ::
          :ok | {:error, Ecto.Changeset.t()}
  def update_item(%Post{id: id}, featured?) do
    update_item(:post_id, id, featured?)
  end

  def update_item(%UserList{id: id}, featured?) do
    update_item(:user_list_id, id, featured?)
  end

  def update_item(%UserTrigger{id: id}, featured?) do
    update_item(:user_trigger_id, id, featured?)
  end

  # Private functions

  defp update_item(type, id, false) do
    from(fi in __MODULE__) |> where(^[{type, id}]) |> Repo.delete_all()
    :ok
  end

  defp update_item(type, id, true) do
    Repo.get_by(__MODULE__, [{type, id}])
    |> case do
      nil -> %__MODULE__{} |> changeset(%{type => id}) |> Repo.insert()
      _result -> :ok
    end
  end

  defp insights_query(), do: from(fi in __MODULE__, where: not is_nil(fi.post_id))
  defp watchlists_query(), do: from(fi in __MODULE__, where: not is_nil(fi.user_list_id))
  defp user_triggers_query(), do: from(fi in __MODULE__, where: not is_nil(fi.user_trigger_id))
end
