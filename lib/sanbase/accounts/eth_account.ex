defmodule Sanbase.Accounts.EthAccount do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.SmartContracts.UniswapPair
  alias Sanbase.Accounts.User

  require Logger
  require Mockery.Macro

  defp ethauth, do: Mockery.Macro.mockable(Sanbase.InternalServices.Ethauth)

  schema "eth_accounts" do
    field(:address, :string)
    belongs_to(:user, User)

    timestamps()
  end

  def changeset(%__MODULE__{} = eth_account, attrs \\ %{}) do
    eth_account
    |> cast(attrs, [
      :address,
      :user_id
    ])
    |> unique_constraint(:address)
  end

  def create(user_id, address) do
    %__MODULE__{}
    |> changeset(%{user_id: user_id, address: address})
    |> Repo.insert()
  end

  @doc ~s"""
  An EthAccount can be removed only if there is another mean to login - an email address
  or another ethereum address set. If the address that is being removed is the only
  address and there is no email, the user account will be lost as there won't be
  any way to log in
  """
  @spec remove(non_neg_integer, String.t()) :: true | {:error, String.t()}
  def remove(user_id, address) do
    if can_remove_eth_account?(user_id, address) do
      case delete_user_address(user_id, address) do
        {1, _} -> true
        {0, _} -> {:error, "Address #{address} does not exist or is not owned by user #{user_id}"}
      end
    else
      {:error,
       "Cannot remove ethereum address #{address}. There must be an email or other ethereum address set."}
    end
  end

  def by_address(address) do
    Repo.get_by(__MODULE__, address: address)
  end

  def all_by_user(user_id) do
    from(ea in __MODULE__, where: ea.user_id == ^user_id)
    |> Repo.all()
  end

  @spec san_balance(%__MODULE__{}) :: float | :error
  def san_balance(%__MODULE__{address: address}) do
    case ethauth().san_balance(address) do
      {:ok, san_balance} ->
        san_balance

      {:error, error} ->
        Logger.error(error)

        :error
    end
  end

  @doc """
  Fetch wallet staked SAN tokens for given Uniswap pair contract
  """
  @spec san_staked_address(String.t(), String.t()) :: float()
  def san_staked_address(address, contract) when is_binary(address) and is_binary(contract) do
    UniswapPair.balance_of(address, contract)
    |> calculate_san_staked(contract_data_map(contract))
  end

  def san_staked_addresses(addresses, contract) when is_list(addresses) and is_binary(contract) do
    data_map = contract_data_map(contract)

    result =
      addresses
      |> Enum.chunk_every(250)
      |> Enum.flat_map(&UniswapPair.balances_of(&1, contract))

    Enum.zip(addresses, result)
    |> Map.new(fn {addr, [balance]} ->
      {addr, calculate_san_staked(balance, data_map)}
    end)
  end

  # Helpers

  defp contract_data_map(contract) do
    %{
      total_supply: UniswapPair.total_supply(contract),
      reserves: UniswapPair.reserves(contract) |> elem(UniswapPair.get_san_position(contract))
    }
  end

  defp calculate_san_staked(address_staked_tokens, _data_map) when address_staked_tokens == 0.0 do
    +0.0
  end

  defp calculate_san_staked(address_staked_tokens, data_map) do
    # Convert the LP tokens to the actual value of SAN tokens
    address_share = address_staked_tokens / data_map.total_supply
    address_share * data_map.reserves
  end

  defp delete_user_address(user_id, address) do
    from(
      ea in __MODULE__,
      where: ea.user_id == ^user_id and ea.address == ^address
    )
    |> Repo.delete_all()
  end

  defp can_remove_eth_account?(user_id, address) do
    {:ok, %User{email: email}} = User.by_id(user_id)

    count_other_accounts =
      all_by_user(user_id)
      |> Enum.map(& &1.address)
      |> Enum.reject(&(&1 == address))
      |> Enum.uniq()
      |> Enum.count()

    count_other_accounts > 0 or not is_nil(email)
  end
end
