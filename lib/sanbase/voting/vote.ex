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
  @spec create(vote_params) ::
          {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    case get_by_opts(attrs |> Keyword.new()) do
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
  end

  @doc ~s"""
  Decreases the votes count for an entityt. If the votes count drops to 0, the vote
  entity is destroyed.
  """
  @spec remove(%__MODULE__{}) ::
          {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def remove(%__MODULE__{} = vote) do
    case vote do
      %__MODULE__{count: 1} ->
        Repo.delete(vote)

      %__MODULE__{count: count} ->
        changeset(vote, %{count: count - 1})
        |> Repo.update()
    end
  end

  def voted_at(%Post{id: post_id}, %User{id: user_id}) do
    from(
      v in __MODULE__,
      select: v.inserted_at,
      where: v.post_id == ^post_id and v.user_id == ^user_id
    )
    |> Repo.one()
  end

  def voted_at(%TimelineEvent{id: timeline_event_id}, %User{id: user_id}) do
    from(
      v in __MODULE__,
      select: v.inserted_at,
      where: v.timeline_event_id == ^timeline_event_id and v.user_id == ^user_id
    )
    |> Repo.one()
  end

  def total_votes(%Post{id: post_id}) do
    from(
      v in __MODULE__,
      select: coalesce(sum(v.count), 0),
      where: v.post_id == ^post_id
    )
    |> Repo.one()
  end

  def total_votes(%TimelineEvent{id: timeline_event_id}) do
    from(
      v in __MODULE__,
      select: coalesce(sum(v.count), 0),
      where: v.timeline_event_id == ^timeline_event_id
    )
    |> Repo.one()
  end

  @spec get_by_opts(vote_kw_list_params) :: %__MODULE__{} | nil
  def get_by_opts(opts) when is_list(opts) do
    Repo.get_by(__MODULE__, opts)
  end
end
