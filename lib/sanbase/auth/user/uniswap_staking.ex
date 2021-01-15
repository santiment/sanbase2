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

  def fetch_san_staked_user(user) do
    user = user |> Repo.preload(:eth_accounts)

    Enum.reduce(user.eth_accounts, 0.0, fn %EthAccount{address: address}, acc ->
      UniswapPair.all_pair_contracts()
      |> Enum.map(&san_staked_address(address, &1))
      |> List.insert_at(-1, acc)
      |> Enum.sum()
    end)
  end

  def san_staked_address(address, contract) do
    address_staked_tokens = UniswapPair.balance_of(address, contract)
    calculate_san_staked(contract, address_staked_tokens)
  end

  # Helpers

  defp calculate_san_staked(_, address_staked_tokens) when address_staked_tokens == 0.0 do
    0.0
  end

  defp calculate_san_staked(contract, address_staked_tokens) do
    san_position_in_pair = UniswapPair.get_san_position(contract)

    total_staked_tokens = UniswapPair.total_supply(contract)
    address_share = address_staked_tokens / total_staked_tokens

    total_san_staked = UniswapPair.reserves(contract) |> Enum.at(san_position_in_pair)
    address_share * total_san_staked
  end
end
