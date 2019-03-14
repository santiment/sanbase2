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
  alias Sanbase.UserLists.UserList
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
  end

  def featured_insights(),
    do: insights_query() |> select([i], i.post_id) |> Repo.all()

  def featured_watchlists(),
    do: watchlists_query() |> select([i], i.user_list_id) |> Repo.all()

  def featured_user_triggers(),
    do: user_triggers_query() |> select([i], i.user_trigger_id) |> Repo.all()

  @doc ~s"""
  Mark the insight as featured or not.

  Update the record for the insight. If it the second argument is `false` any
  present record will be deleted. If the second argument is `true` a new record
  will be created if it does not exist
  """
  @spec update_insight(%Post{}, boolean) ::
          :ok | {:error, Ecto.Changeset.t()}
  def update_insight(%Post{id: id}, featured?) do
    update_element(:post_id, id, featured?)
  end

  @doc ~s"""
  Mark the watchlist as featured or not.

  Update the record for the watchlist. If it the second argument is `false` any
  present record will be deleted. If the second argument is `true` a new record
  will be created if it does not exist
  """
  @spec update_watchlist(%UserList{}, boolean) ::
          :ok | {:error, Ecto.Changeset.t()}
  def update_watchlist(%UserList{id: id}, featured?) do
    update_element(:user_list_id, id, featured?)
  end

  @doc ~s"""
  Mark the user_trigger as featured or not.

  Update the record for the user_trigger. If it the second argument is `false` any
  present record will be deleted. If the second argument is `true` a new record
  will be created if it does not exist
  """
  @spec update_user_trigger(%UserTrigger{}, boolean) ::
          :ok | {:error, Ecto.Changeset.t()}
  def update_user_trigger(%UserTrigger{id: id}, featured?) do
    update_element(:user_trigger_id, id, featured?)
  end

  # Private functions

  defp update_element(type, id, false) do
    from(fi in __MODULE__) |> where(^[{type, id}]) |> Repo.delete_all()
    :ok
  end

  defp update_element(type, id, true) do
    from(fi in __MODULE__, where: ^[{type, id}])
    |> Repo.get_by([])
    |> case do
      nil -> %__MODULE__{} |> changeset(%{type => id}) |> Repo.insert()
      result -> :ok
    end
  end

  defp insights_query(), do: from(fi in __MODULE__, where: not is_nil(fi.post_id))
  defp watchlists_query(), do: from(fi in __MODULE__, where: not is_nil(fi.user_list_id))
  defp user_triggers_query(), do: from(fi in __MODULE__, where: not is_nil(fi.user_trigger_id))
end
