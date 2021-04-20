defmodule Sanbase.WalletHunters.RelayQuota do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Accounts.User
  alias Sanbase.Repo

  @free_ops_global_quota 100
  @proposals_per_user_quota 2
  @votes_per_user_quota 3
  # 2 weeks
  @votes_reset_interval_in_days 14

  schema "wallet_hunters_relays_quota" do
    field(:proposals_used, :integer, default: 0)
    field(:proposals_earned, :integer, default: 0)
    field(:votes_used, :integer, default: 0)
    field(:last_voted, :utc_datetime)

    belongs_to(:user, User)

    timestamps()
  end

  @doc false
  def changeset(relay_quota, attrs) do
    relay_quota
    |> cast(attrs, [:user_id, :proposals_used, :proposals_earned, :votes_used, :last_voted])
    |> validate_required([:user_id])
  end

  def by_user(user_id) do
    Repo.get_by(__MODULE__, user_id: user_id)
  end

  def create(params) do
    %__MODULE__{}
    |> changeset(params)
    |> Repo.insert()
  end

  def update_quota(relays_quota, params) do
    relays_quota
    |> changeset(params)
    |> Repo.update()
  end

  def update_earned_proposals(user_id, proposals_earned) do
    by_user(user_id)
    |> case do
      nil ->
        :ok

      %__MODULE__{} = relays_quota ->
        update_quota(relays_quota, %{proposals_earned: proposals_earned})
    end
  end

  def create_or_update(user_id) do
    with true <- can_relay?(user_id) do
      by_user(user_id)
      |> case do
        nil ->
          create(%{user_id: user_id, proposals_used: 1})

        %__MODULE__{proposals_used: proposals_used} = relays_quota ->
          update_quota(relays_quota, %{proposals_used: proposals_used + 1})
      end
    end
  end

  def create_or_update(user_id, %{type: :vote}) do
    with true <- can_relay?(user_id, %{type: :vote}) do
      by_user(user_id)
      |> case do
        nil ->
          create(%{user_id: user_id, votes_used: 1, last_voted: Timex.now()})

        %__MODULE__{votes_used: votes_used} = relays_quota ->
          update_quota(relays_quota, %{votes_used: votes_used + 1, last_voted: Timex.now()})
      end
    end
  end

  def relays_quota(user_id) do
    can_relay_proposal =
      case can_relay?(user_id) do
        true -> true
        {:error, _} -> false
      end

    can_relay_vote =
      case can_relay?(user_id, %{type: :vote}) do
        true -> true
        {:error, _} -> false
      end

    get_relays(user_id)
    |> Map.merge(%{can_relay_proposal: can_relay_proposal})
    |> Map.merge(%{can_relay_vote: can_relay_vote})
  end

  def can_relay?(user_id) do
    get_relays(user_id)
    |> case do
      %{global_relays_left: global_relays_left} when global_relays_left <= 0 ->
        {:error, "Global relays limit reached!"}

      %{proposal_relays_left: proposal_relays_left} when proposal_relays_left <= 0 ->
        {:error, "Proposal relays limit reached!"}

      %{global_relays_left: global_relays_left, proposal_relays_left: proposal_relays_left}
      when global_relays_left > 0 and proposal_relays_left > 0 ->
        true
    end
  end

  def can_relay?(user_id, %{type: :vote}) do
    get_relays(user_id)
    |> case do
      %{global_relays_left: global_relays_left} when global_relays_left <= 0 ->
        {:error, "Global relays limit reached!"}

      %{votes_relays_left: votes_relays_left} when votes_relays_left <= 0 ->
        {:error, "Votes relays limit reached!"}

      %{global_relays_left: global_relays_left, votes_relays_left: votes_relays_left}
      when global_relays_left > 0 and votes_relays_left > 0 ->
        true
    end
  end

  def get_relays(user_id) do
    Map.merge(get_globals(), proposals_for_user(user_id))
    |> Map.merge(votes_for_user(user_id))
  end

  def get_globals() do
    from(u in __MODULE__, select: {sum(u.proposals_used), sum(u.votes_used)})
    |> Repo.one()
    |> case do
      nil ->
        {
          @free_ops_global_quota,
          0,
          @free_ops_global_quota
        }
        |> to_map_global()

      {proposals_used, votes_used} ->
        used = (proposals_used || 0) + (votes_used || 0)
        {@free_ops_global_quota, used, @free_ops_global_quota - used} |> to_map_global()
    end
  end

  def proposals_for_user(user_id) do
    from(u in __MODULE__,
      where: u.user_id == ^user_id,
      select: {u.proposals_used, u.proposals_earned}
    )
    |> Repo.one()
    |> case do
      nil ->
        {@proposals_per_user_quota, 0, @proposals_per_user_quota} |> to_map_proposals()

      {relays_used, relays_earned} ->
        relays_earned = min(@proposals_per_user_quota, relays_earned)
        relays_used = max(relays_used - relays_earned, 0)

        {@proposals_per_user_quota, relays_used, @proposals_per_user_quota - relays_used}
        |> to_map_proposals()
    end
  end

  def votes_for_user(user_id) do
    from(u in __MODULE__, where: u.user_id == ^user_id, select: {u.votes_used, u.last_voted})
    |> Repo.one()
    |> case do
      nil ->
        {@votes_per_user_quota, 0, @votes_per_user_quota} |> to_map_votes()

      {relays_used, last_voted} ->
        relays_used =
          if Timex.diff(Timex.now(), last_voted, :days) >= @votes_reset_interval_in_days do
            0
          else
            relays_used
          end

        {@votes_per_user_quota, relays_used, @votes_per_user_quota - relays_used}
        |> to_map_votes()
    end
  end

  defp to_map_proposals({quota, used, left}) do
    %{
      proposal_relays_quota: quota,
      proposal_relays_used: used,
      proposal_relays_left: left
    }
  end

  defp to_map_votes({quota, used, left}) do
    %{
      votes_relays_quota: quota,
      votes_relays_used: used,
      votes_relays_left: left
    }
  end

  defp to_map_global({quota, used, left}) do
    %{
      global_relays_quota: quota,
      global_relays_used: used,
      global_relays_left: left
    }
  end
end
