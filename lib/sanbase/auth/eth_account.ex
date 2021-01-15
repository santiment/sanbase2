defmodule Sanbase.Auth.EthAccount do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Repo
  alias Sanbase.Auth.User
  alias Sanbase.SmartContracts.UniswapPair

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

  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  def by_address(address) do
    Repo.get_by(__MODULE__, address: address)
  end

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
  def san_staked_address(address, contract) do
    UniswapPair.balance_of(address, contract)
    |> calculate_san_staked(contract)
  end

  # Helpers

  defp calculate_san_staked(_, address_staked_tokens) when address_staked_tokens == 0.0 do
    0.0
  end

  defp calculate_san_staked(address_staked_tokens, contract) do
    san_position_in_pair = UniswapPair.get_san_position(contract)

    total_staked_tokens = UniswapPair.total_supply(contract)
    address_share = address_staked_tokens / total_staked_tokens

    total_san_staked = UniswapPair.reserves(contract) |> elem(san_position_in_pair)
    address_share * total_san_staked
  end
end
