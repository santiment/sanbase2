defmodule Sanbase.Accounts.EthAccount do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  import Sanbase.Utils.Transform, only: [maybe_apply_function: 2]

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

  def all() do
    Repo.all(__MODULE__)
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
    lowercase_address = String.downcase(address)

    from(ea in __MODULE__,
      where: fragment("LOWER(?)", ea.address) == ^lowercase_address
    )
    |> Repo.one()
  end

  def all_by_user(user_id) do
    from(ea in __MODULE__, where: ea.user_id == ^user_id)
    |> Repo.all()
  end

  def address_to_user_id_map(addresses) when is_list(addresses) do
    lowercase_addresses = Enum.map(addresses, &String.downcase/1)

    from(
      ea in __MODULE__,
      where: fragment("LOWER(?)", ea.address) in ^lowercase_addresses,
      select: {ea.address, ea.user_id}
    )
    |> Repo.all()
    |> Map.new(fn {address, user_id} ->
      {Sanbase.BlockchainAddress.to_internal_format(address), user_id}
    end)
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
  Fetch wallet staked SAN tokens for given Uniswap pair contract.

  A failed contract call is treated as no staked tokens, so this function is
  suitable only for best-effort read paths, not for persisting data.
  """
  @spec san_staked_address(String.t(), String.t()) :: float()
  def san_staked_address(address, contract) when is_binary(address) and is_binary(contract) do
    case contract_data_map(contract) do
      {:ok, data_map} ->
        UniswapPair.balance_of(address, contract)
        |> calculate_san_staked(data_map)

      {:error, _} ->
        +0.0
    end
  end

  @doc """
  Fetch the staked SAN tokens of each address for the given Uniswap pair
  contract.

  The addresses are queried in batches of 90, as the RPC node rejects
  batches larger than 100 requests. Any failed contract call fails the
  whole function, so an RPC outage cannot be mistaken for zero balances.

  ## Examples

      iex> EthAccount.san_staked_addresses([addr1, addr2], contract)
      {:ok, %{addr1 => 150.0, addr2 => 0.0}}

      iex> EthAccount.san_staked_addresses([addr1, addr2], contract)
      {:error, %Finch.TransportError{reason: :nxdomain}}
  """
  @spec san_staked_addresses([String.t()], String.t()) ::
          {:ok, %{String.t() => float()}} | {:error, any()}
  def san_staked_addresses(addresses, contract) when is_list(addresses) and is_binary(contract) do
    with {:ok, data_map} <- contract_data_map(contract) do
      addresses
      |> Enum.chunk_every(90)
      |> Enum.reduce_while({:ok, []}, fn chunk, {:ok, acc} ->
        case UniswapPair.balances_of(chunk, contract) do
          {:ok, balances} -> {:cont, {:ok, [balances | acc]}}
          {:error, _} = error -> {:halt, error}
        end
      end)
      |> maybe_apply_function(fn balances_chunks ->
        balances = balances_chunks |> Enum.reverse() |> List.flatten()

        Enum.zip(addresses, balances)
        |> Map.new(fn {addr, balance} ->
          {addr, calculate_san_staked(balance, data_map)}
        end)
      end)
    end
  end

  # Helpers

  defp contract_data_map(contract) do
    with total_supply when is_float(total_supply) <- UniswapPair.total_supply(contract),
         {reserves0, reserves1} when is_float(reserves0) and is_float(reserves1) <-
           UniswapPair.reserves(contract),
         position when position in [0, 1] <- UniswapPair.get_san_position(contract) do
      {:ok,
       %{
         total_supply: total_supply,
         reserves: elem({reserves0, reserves1}, position)
       }}
    else
      {:error, _} = error -> error
      unexpected -> {:error, {:invalid_contract_data, unexpected}}
    end
  end

  defp calculate_san_staked(address_staked_tokens, _data_map) when address_staked_tokens == 0.0 do
    +0.0
  end

  defp calculate_san_staked(_address_staked_tokens, %{total_supply: total_supply})
       when total_supply == 0.0 do
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
