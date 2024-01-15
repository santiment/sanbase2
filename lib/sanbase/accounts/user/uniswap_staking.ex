defmodule Sanbase.Accounts.User.UniswapStaking do
  use Ecto.Schema
  import Ecto.Changeset

  require Logger

  alias Sanbase.Repo
  alias Sanbase.Accounts.{User, EthAccount}
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
  Fetch all staked users over certain amount
  """
  def fetch_all_uniswap_staked_users() do
    __MODULE__ |> Repo.all()
  end

  @doc """
  Fetch all users with conncted wallets, fetch their total staked
  SAN tokens and update.
  """
  @spec update_all_uniswap_san_staked_users() ::
          {:ok, {integer(), nil | [term()]}} | {:error, any()}
  def update_all_uniswap_san_staked_users() do
    Logger.info("Start update_all_uniswap_san_staked_users")
    naive_now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    users = User.fetch_all_users_with_eth_account()
    users_staked_map = fetch_uniswap_san_staked(users)

    users_san_staked =
      users
      |> Enum.map(fn user ->
        san_staked = user_san_staked_amount(user, users_staked_map)

        %{
          user_id: user.id,
          san_staked: san_staked,
          inserted_at: naive_now,
          updated_at: naive_now
        }
      end)
      |> Enum.filter(&(&1.san_staked > 0.0))

    Repo.transaction(fn ->
      Repo.delete_all(__MODULE__)

      Repo.insert_all(
        __MODULE__,
        users_san_staked,
        on_conflict: :replace_all,
        conflict_target: [:user_id]
      )
    end)
    |> case do
      {:ok, result} ->
        Logger.info("Finished update_all_uniswap_san_staked_users ok: #{inspect(result)}")
        {:ok, result}

      {:error, reason} ->
        Logger.error("Finished update_all_uniswap_san_staked_users error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetch the total SAN tokens staked as liquidity provider in Uniswap
  pair contracts that we follow for all connected user wallets.
  """
  @spec fetch_uniswap_san_staked_user(%User{} | non_neg_integer()) :: float()
  def fetch_uniswap_san_staked_user(%User{} = user) do
    user = user |> Repo.preload(:eth_accounts)
    calc_uniswap_san_staked_user(user)
  end

  def fetch_uniswap_san_staked_user(user_id) do
    {:ok, user} = User.by_id(user_id)
    user = user |> Repo.preload(:eth_accounts)

    calc_uniswap_san_staked_user(user)
  end

  # Helpers
  defp fetch_uniswap_san_staked(users) when is_list(users) do
    addresses =
      Enum.flat_map(users, fn user -> Enum.map(user.eth_accounts, fn acc -> acc.address end) end)

    UniswapPair.all_pair_contracts()
    |> Enum.map(&EthAccount.san_staked_addresses(addresses, &1))
    |> Enum.reduce(%{}, &Map.merge(&1, &2, fn _k, v1, v2 -> v1 + v2 end))
  end

  defp calc_uniswap_san_staked_user(user) do
    Enum.reduce(user.eth_accounts, +0.0, fn %EthAccount{address: address}, acc ->
      UniswapPair.all_pair_contracts()
      |> Enum.map(&EthAccount.san_staked_address(address, &1))
      |> List.insert_at(-1, acc)
      |> Enum.sum()
    end)
  end

  defp user_san_staked_amount(user, users_staked_map) do
    user.eth_accounts
    |> Enum.map(fn account -> Map.get(users_staked_map, account.address, 0) end)
    |> Enum.sum()
  end
end
