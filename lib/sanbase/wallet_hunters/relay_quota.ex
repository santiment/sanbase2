defmodule Sanbase.WalletHunters.RelayQuota do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Accounts.User
  alias Sanbase.Repo

  @free_ops_global_quota 100
  @proposals_per_user_quota 2

  schema "wallet_hunters_relays_quota" do
    field(:proposals_used, :integer, default: 0)

    belongs_to(:user, User)

    timestamps()
  end

  @doc false
  def changeset(relay_quota, attrs) do
    relay_quota
    |> cast(attrs, [:user_id, :proposals_used])
    |> validate_required([:user_id, :proposals_used])
  end

  def create_or_update(user_id) do
    with true <- can_relay?(user_id) do
      Repo.get_by(__MODULE__, user_id: user_id)
      |> case do
        nil ->
          %__MODULE__{}
          |> changeset(%{user_id: user_id, proposals_used: 1})
          |> Repo.insert()

        %__MODULE__{proposals_used: proposals_used} = relays_quota ->
          relays_quota
          |> changeset(%{proposals_used: proposals_used + 1})
          |> Repo.update()
      end
    end
  end

  def relays_quota(user_id) do
    can_relay_proposal =
      case can_relay?(user_id) do
        true -> true
        {:error, _} -> false
      end

    get_relays(user_id)
    |> Map.merge(%{can_relay_proposal: can_relay_proposal})
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

  def get_relays(user_id) do
    Map.merge(get_globals(), for_user(user_id))
  end

  def get_globals() do
    from(u in __MODULE__, select: sum(u.proposals_used))
    |> Repo.one()
    |> case do
      nil -> {@free_ops_global_quota, 0, @free_ops_global_quota} |> to_map_global()
      used -> {@free_ops_global_quota, used, @free_ops_global_quota - used} |> to_map_global()
    end
  end

  def for_user(user_id) do
    from(u in __MODULE__, where: u.user_id == ^user_id, select: u.proposals_used)
    |> Repo.one()
    |> case do
      nil ->
        {@proposals_per_user_quota, 0, @proposals_per_user_quota} |> to_map_per_user()

      relays_used ->
        {@proposals_per_user_quota, relays_used, @proposals_per_user_quota - relays_used}
        |> to_map_per_user()
    end
  end

  defp to_map_per_user({quota, used, left}) do
    %{
      proposal_relays_quota: quota,
      proposal_relays_used: used,
      proposal_relays_left: left
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
