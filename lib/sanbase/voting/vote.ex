defmodule Sanbase.Vote do
  @moduledoc """
  Module for voting for insights and timeline events.
  """
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Repo
  alias Sanbase.Insight.Post
  alias Sanbase.Timeline.TimelineEvent
  alias Sanbase.Auth.User

  @type vote_params :: %{
          :user_id => non_neg_integer(),
          optional(:timeline_event_id) => non_neg_integer(),
          optional(:post_id) => non_neg_integer()
        }

  @type vote_kw_list_params :: [
          user_id: non_neg_integer(),
          timeline_event_id: non_neg_integer(),
          post_id: non_neg_integer()
        ]

  @max_votes 20

  schema "votes" do
    field(:count, :integer)

    belongs_to(:post, Post)
    belongs_to(:timeline_event, TimelineEvent)
    belongs_to(:user, User)

    timestamps()
  end

  def changeset(%__MODULE__{} = vote, attrs \\ %{}) do
    vote
    |> cast(attrs, [:post_id, :timeline_event_id, :user_id, :count])
    |> validate_required([:user_id])
    |> unique_constraint(:post_id,
      name: :votes_post_id_user_id_index
    )
    |> unique_constraint(:timeline_event_id,
      name: :votes_timeline_event_id_user_id_index
    )
  end

  @doc ~s"""
  Create a new vote entity or increases the votes count up to #{@max_votes}.
  """
  @spec create(vote_params) :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:select_if_exists, fn _repo, _changes ->
      {:ok, get_by_opts(attrs |> Keyword.new())}
    end)
    |> Ecto.Multi.run(:create_or_increase_count, fn _repo, %{select_if_exists: vote} ->
      case vote do
        nil ->
          attrs = Map.put(attrs, :count, 1)

          %__MODULE__{}
          |> changeset(attrs)
          |> Repo.insert()

        %__MODULE__{count: @max_votes} = vote ->
          {:ok, vote}

        %__MODULE__{count: count} = vote ->
          changeset(vote, %{count: count + 1})
          |> Repo.update()
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{create_or_increase_count: vote}} -> {:ok, vote}
      {:error, _name, error, _} -> {:error, error}
    end
  end

  @doc ~s"""
  Decreases the votes count for an entityt. If the votes count drops to 0, the vote
  entity is destroyed.
  """
  @spec downvote(vote_params) :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def downvote(attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:select_if_exists, fn _repo, _changes ->
      {:ok, get_by_opts(attrs |> Keyword.new())}
    end)
    |> Ecto.Multi.run(:decrease_count_or_destroy, fn _repo, %{select_if_exists: vote} ->
      case vote do
        nil ->
          {:ok, %__MODULE__{}}

        %__MODULE__{count: 1} ->
          Repo.delete(vote)

        %__MODULE__{count: count} ->
          changeset(vote, %{count: count - 1})
          |> Repo.update()
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{decrease_count_or_destroy: vote}} -> {:ok, vote}
      {:error, _name, error, _} -> {:error, error}
    end
  end

  def voted_at(entity, %User{id: user_id}) do
    entity_query(entity)
    |> by_user_query(user_id)
    |> select([v], v.inserted_at)
    |> Repo.one()
  end

  def vote_stats(entity, user \\ nil)

  def vote_stats(entity, nil) do
    {total_votes, total_voters} =
      total_votes_query(entity)
      |> Repo.one()

    %{
      total_votes: total_votes,
      total_voters: total_voters,
      current_user_votes: nil
    }
  end

  def vote_stats(entity, %User{id: user_id}) do
    {total_votes, total_voters} =
      total_votes_query(entity)
      |> Repo.one()

    current_user_votes = total_votes_of_user_query(entity, user_id) |> Repo.one()

    %{
      total_votes: total_votes,
      total_voters: total_voters,
      current_user_votes: current_user_votes
    }
  end

  @spec get_by_opts(vote_kw_list_params) :: %__MODULE__{} | nil
  def get_by_opts(opts) when is_list(opts) do
    Repo.get_by(__MODULE__, opts)
  end

  # Private functions

  defp total_votes_query(entity) do
    entity_query(entity)
    |> select([v], {coalesce(sum(v.count), 0), count(fragment("DISTINCT ?", v.user_id))})
  end

  defp total_votes_of_user_query(entity, user_id) do
    entity_query(entity)
    |> by_user_query(user_id)
    |> select([v], coalesce(sum(v.count), 0))
  end

  defp by_user_query(query, user_id) do
    from(
      v in query,
      where: v.user_id == ^user_id
    )
  end

  defp entity_query(%Post{id: post_id}), do: from(v in __MODULE__, where: v.post_id == ^post_id)

  defp entity_query(%TimelineEvent{id: timeline_event_id}),
    do: from(v in __MODULE__, where: v.timeline_event_id == ^timeline_event_id)
end
