defmodule Sanbase.Clickhouse.Erc20Transfers do
  @moduledoc ~s"""
  Uses ClickHouse to work with ERC20 transfers.
  """
  use Ecto.Schema

  import Ecto.Query
  import Sanbase.Clickhouse.EctoFunctions

  alias Sanbase.ClickhouseRepo
  alias __MODULE__

  @primary_key false
  @timestamps_opts updated_at: false
  schema "erc20_transfers" do
    field(:dt, :utc_datetime, primary_key: true)
    field(:contract, :string, primary_key: true)
    field(:from, :string, primary_key: true)
    field(:to, :string, primary_key: true)
    field(:transactionHash, :string, primary_key: true)
    field(:value, :float)
    field(:blockNumber, :integer)
    field(:logIndex, :integer)
  end

  def changeset(_, _attrs \\ %{}) do
    raise "Should not try to change eth daily active addresses"
  end

  @doc ~s"""
  Return the `limit` biggest transaction for a given contract and time period.
  If the top transactions for SAN token are needed, the SAN contract address must be
  provided as a first argument.
  """
  def token_top_transfers(contract, from_datetime, to_datetime, limit \\ 10) do
    from(
      transfer in Erc20Transfers,
      where:
        transfer.contract == ^contract and transfer.dt > ^from_datetime and
          transfer.dt < ^to_datetime,
      order_by: [desc: transfer.value],
      limit: ^limit
    )
    |> query_all_use_prewhere()
  end

  def count_contract_transfers(contract, from_datetime, to_datetime) do
    from(
      transfer in Erc20Transfers,
      where:
        transfer.contract == ^contract and transfer.dt > ^from_datetime and
          transfer.dt < ^to_datetime,
      select: count("*")
    )
    |> query_all_use_prewhere()
  end
end
