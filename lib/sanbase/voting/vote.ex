defmodule Sanbase.Vote do
  @moduledoc """
  Module for voting for insights and timeline events.
  """
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Repo
  alias Sanbase.Accounts.User

  alias Sanbase.Chart
  alias Sanbase.Insight.Post
  alias Sanbase.UserList
  alias Sanbase.Timeline.TimelineEvent
  alias Sanbase.Alert.UserTrigger

  @type vote_params :: %{
          :user_id => non_neg_integer(),
          optional(:post_id) => non_neg_integer(),
          optional(:watchlist_id) => non_neg_integer(),
          optional(:timeline_event_id) => non_neg_integer(),
          optional(:chart_configuration_id) => non_neg_integer(),
          optional(:user_trigger_id) => non_neg_integer(),
          optional(:dashboard_id) => non_neg_integer(),
          optional(:query_id) => non_neg_integer()
        }

  @type vote_option ::
          {:user_id, non_neg_integer()}
          | {:post_id, non_neg_integer()}
          | {:watchlist_id, non_neg_integer()}
          | {:timeline_event_id, non_neg_integer()}
          | {:chart_configuration_id, non_neg_integer()}
          | {:user_trigger_id, non_neg_integer()}
          | {:dashboard_id, non_neg_integer()}
          | {:query_id, non_neg_integer()}
  @type vote_kw_list_params :: [vote_option]

  @max_votes 20

  schema "votes" do
    field(:count, :integer)

    belongs_to(:user, User)

    belongs_to(:post, Post)
    belongs_to(:timeline_event, TimelineEvent)
    belongs_to(:watchlist, UserList, foreign_key: :watchlist_id)

    belongs_to(:chart_configuration, Chart.Configuration, foreign_key: :chart_configuration_id)

    belongs_to(:user_trigger, UserTrigger, foreign_key: :user_trigger_id)
    belongs_to(:dashboard, Sanbase.Dashboards.Dashboard, foreign_key: :dashboard_id)
    belongs_to(:query, Sanbase.Queries.Query, foreign_key: :query_id)

    timestamps()
  end

  def changeset(%__MODULE__{} = vote, attrs \\ %{}) do
    vote
    |> cast(attrs, [
      :user_id,
      :count,
      :post_id,
      :timeline_event_id,
      :chart_configuration_id,
      :user_trigger_id,
      :watchlist_id,
      :dashboard_id,
      :query_id
    ])
    |> validate_required([:user_id])
    |> unique_constraint(:post_id, name: :votes_post_id_user_id_index)
    |> unique_constraint(:timeline_event_id, name: :votes_timeline_event_id_user_id_index)
    |> unique_constraint(:chart_configuration_id,
      name: :votes_chart_configuration_id_user_id_index
    )
    |> unique_constraint(:watchlist_id, name: :votes_watchlist_id_user_id_index)
    |> unique_constraint(:user_trigger_id, name: :votes_user_trigger_id_user_id_index)
    |> unique_constraint(:dashboard_id, name: :votes_dashboard_id_index)
    |> unique_constraint(:query_id, name: :votes_query_id_index)
  end

  @doc ~s"""
  Create a new vote entity or increases the votes count up to #{@max_votes}.
  """
  @spec create(vote_params) ::
          {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
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
  @spec downvote(vote_params) ::
          {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
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
          with {:ok, _} <- Repo.delete(vote), do: {:ok, %__MODULE__{}}

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

  def voted_at(entity_type, entity_ids, user_id) when is_integer(user_id) do
    voted_at_query(entity_type, entity_ids, user_id)
    |> Repo.all()
  end

  def vote_stats(entity_type, entity_ids, user_id \\ nil) do
    result =
      total_votes_query(entity_type, entity_ids, user_id)
      |> Repo.all()

    # Override `:current_user_votes` with nil if the user_id is nil
    # The SQL query returns 0 in these cases
    case user_id do
      nil -> result |> Enum.map(&Map.put(&1, :current_user_votes, nil))
      _ -> result
    end
  end

  @spec post_id_to_votes() :: map()
  def post_id_to_votes() do
    from(
      v in __MODULE__,
      group_by: v.post_id,
      select: {v.post_id, count(v.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @spec get_by_opts(vote_kw_list_params) :: %__MODULE__{} | nil
  def get_by_opts(opts) when is_list(opts) do
    Repo.get_by(__MODULE__, opts)
  end

  def user_total_votes(user_id) do
    query =
      from(
        v in __MODULE__,
        where: v.user_id == ^user_id,
        select: %{
          insight_votes: fragment("COUNT(CASE WHEN post_id IS NOT NULL THEN 1 ELSE 0 END)"),
          watchlist_votes:
            fragment("COUNT(CASE WHEN watchlist_id IS NOT NULL THEN 1 ELSE 0 END)"),
          chart_configuration_votes:
            fragment("COUNT(CASE WHEN chart_configuration_id IS NOT NULL THEN 1 ELSE 0 END)"),
          alert_votes: fragment("COUNT(CASE WHEN user_trigger_id IS NOT NULL THEN 1 ELSE 0 END)"),
          dashboard_votes:
            fragment("COUNT(CASE WHEN dashboard_id IS NOT NULL THEN 1 ELSE 0 END)"),
          query_votes: fragment("COUNT(CASE WHEN query_id IS NOT NULL THEN 1 ELSE 0 END)")
        }
      )

    votes = Repo.one(query)
    # Put the total_votes as a separate field
    votes = Map.put(votes, :total_votes, Enum.sum(Map.values(votes)))

    {:ok, votes}
  end

  # Private functions

  defp total_votes_query(entity_type, entity_ids, user_id) do
    # Override nil with -1 so the checks for current user
    # votes will return 0
    user_id = user_id || -1
    entity_field = Sanbase.Entity.deduce_entity_vote_field(entity_type)

    from(
      vote in entities_query(entity_type, entity_ids),
      group_by: field(vote, ^entity_field),
      select: %{
        entity_id: field(vote, ^entity_field),
        total_votes: coalesce(sum(vote.count), 0),
        total_voters: count(fragment("DISTINCT ?", vote.user_id)),
        current_user_votes:
          fragment(
            "SUM(CASE when user_id = ? then ? else 0 end)",
            ^user_id,
            vote.count
          )
      }
    )
  end

  defp voted_at_query(entity_type, entity_ids, user_id) do
    entity_field = Sanbase.Entity.deduce_entity_vote_field(entity_type)

    from(
      vote in entities_query(entity_type, entity_ids),
      where: vote.user_id == ^user_id,
      select: %{
        entity_id: field(vote, ^entity_field),
        voted_at: vote.inserted_at
      }
    )
  end

  defp entities_query(entity_type, entity_ids) do
    entity_field = Sanbase.Entity.deduce_entity_vote_field(entity_type)

    from(
      vote in __MODULE__,
      where: field(vote, ^entity_field) in ^entity_ids
    )
  end
end
