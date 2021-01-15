defmodule Sanbase.Auth.User.UniswapStaking do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Repo
  alias Sanbase.Auth.{User, EthAccount}
  alias Sanbase.SmartContracts.UniswapPair

  schema "user_uniswap_staking" do
    field(:san_staked, :float)
    belongs_to(:user, User)

    timestamps()
  end

  @doc false
  def changeset(uniswap_staking, attrs) do
    uniswap_staking
    |> cast(attrs, [:san_staked])
    |> validate_required([:san_staked])
  end

  @doc """
  Fetch all users with conncted wallets, fetch their total staked
  SAN tokens and update.
  """
  @spec update_all_san_staked_users() :: {integer(), nil | [term()]}
  def update_all_san_staked_users() do
    naive_now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    users_san_staked =
      User.fetch_all_users_with_eth_account()
      |> Enum.map(fn user ->
        %{
          user_id: user.id,
          san_staked: fetch_san_staked_user(user),
          inserted_at: naive_now,
          updated_at: naive_now
        }
      end)
      |> Enum.filter(&(&1.san_staked > 0.0))

    Repo.insert_all(
      __MODULE__,
      users_san_staked,
      on_conflict: :replace_all,
      conflict_target: [:user_id]
    )
  end

  @doc """
  Fetch the total SAN tokens staked as liquidity provider in Uniswap
  pair contracts that we follow for all connected user wallets.
  """
  @spec fetch_san_staked_user(%User{}) :: float()
  def fetch_san_staked_user(user) do
    user = user |> Repo.preload(:eth_accounts)

    Enum.reduce(user.eth_accounts, 0.0, fn %EthAccount{address: address}, acc ->
      UniswapPair.all_pair_contracts()
      |> Enum.map(&EthAccount.san_staked_address(address, &1))
      |> List.insert_at(-1, acc)
      |> Enum.sum()
    end)
  end
end
