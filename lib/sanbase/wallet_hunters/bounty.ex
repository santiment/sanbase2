defmodule Sanbase.WalletHunters.Bounty do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Accounts.User

  schema "wallet_hunters_bounties" do
    field(:title, :string)
    field(:description, :string)
    field(:duration, :string)
    field(:proposal_reward, :integer)
    field(:proposals_count, :integer)
    field(:transaction_id, :string)
    field(:transaction_status, :string, default: "pending")
    field(:hash_digest, :string)

    belongs_to(:user, User)

    timestamps()
  end

  @doc false
  def changeset(bounty, attrs) do
    bounty
    |> cast(attrs, [
      :user_id,
      :title,
      :description,
      :duration,
      :proposals_count,
      :proposal_reward,
      :transaction_id,
      :transaction_status,
      :hash_digest
    ])
    |> validate_required([
      :user_id,
      :title,
      :description,
      :duration,
      :proposals_count,
      :proposal_reward,
      :transaction_id,
      :transaction_status
    ])
  end

  def create_bounty(user_id, args) do
    hash_digest = :crypto.hash(:sha256, Jason.encode!(args)) |> Base.encode16()

    args
    |> Map.put(:user_id, user_id)
    |> Map.put(:hash_digest, hash_digest)
    |> create_db_bounty()
  end

  def by_id(id) do
    from(b in __MODULE__, where: b.id == ^id, preload: [:user])
    |> Repo.one()
  end

  def list_bounties() do
    from(b in __MODULE__, preload: [:user])
    |> Repo.all()
  end

  # helpers
  defp create_db_bounty(args) do
    changeset(%__MODULE__{}, args)
    |> Repo.insert()
    |> preload()
  end

  defp preload({:ok, bounty}) do
    {:ok, Repo.preload(bounty, :user)}
  end

  defp preload(error), do: error
end
