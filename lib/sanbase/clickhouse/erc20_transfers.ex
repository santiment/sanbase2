defmodule Sanbase.Clickhouse.Erc20Transfers do
  @moduledoc ~s"""
  Uses ClickHouse to work with ERC20 transfers.
  """
  use Ecto.Schema

  import Ecto.Query

  alias __MODULE__
  require Sanbase.ClickhouseRepo
  alias Sanbase.ClickhouseRepo

  @primary_key false
  @timestamps_opts updated_at: false

  schema "erc20_transfers" do
    field(:datetime, :utc_datetime, source: :dt)
    field(:contract, :string, primary_key: true)
    field(:from_address, :string, primary_key: true, source: :from)
    field(:to_address, :string, primary_key: true, source: :to)
    field(:trx_hash, :string, source: :transactionHash)
    field(:trx_value, :float, source: :value)
    field(:block_number, :integer, source: :blockNumber)
    field(:trx_position, :integer, source: :transactionPosition)
    field(:log_index, :integer, source: :logIndex)
  end

  def changeset(_, _attrs \\ %{}) do
    raise "Should not try to change eth daily active addresses"
  end

  @doc ~s"""
  Return the `limit` biggest transaction for a given contract and time period.
  If the top transactions for SAN token are needed, the SAN contract address must be
  provided as a first argument.
  """
  def token_top_transfers(contract, from_datetime, to_datetime, limit, token_decimals \\ 0) do
    token_decimals = :math.pow(10, token_decimals)

    from(
      transfer in Erc20Transfers,
      where:
        transfer.contract == ^contract and transfer.datetime > ^from_datetime and
          transfer.datetime < ^to_datetime,
      select: %{
        datetime: transfer.datetime,
        from_address: transfer.from_address,
        to_address: transfer.to_address,
        trx_hash: transfer.trx_hash,
        trx_value: fragment("divide(?,?) as value", transfer.trx_value, ^token_decimals)
      },
      order_by: [desc: transfer.trx_value],
      limit: ^limit
    )
    |> ClickhouseRepo.all_prewhere()
  end
end
