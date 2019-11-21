defmodule Sanbase.Clickhouse.HistoricalBalance.Erc20Balance do
  @doc ~s"""
  Module for working with historical ERC20 balances.

  Includes functions for calculating:
  - Historical balances for an address
  - Balance changes for and address
  """

  @behaviour Sanbase.Clickhouse.HistoricalBalance.Behaviour
  use Ecto.Schema

  import Sanbase.Clickhouse.HistoricalBalance.Utils

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @typedoc ~s"""
  An interval represented as string. It has the format of number followed by one of:
  ns, ms, s, m, h, d or w - each representing some time unit
  """
  @type interval :: String.t()
  @type address :: String.t()
  @type contract :: String.t()
  @type token_decimals :: non_neg_integer()

  @type historical_balance :: %{
          datetime: non_neg_integer(),
          balance: float
        }

  @type slug_balance_map :: %{
          slug: String.t(),
          balance: float()
        }

  @table "erc20_balances"
  schema @table do
    field(:datetime, :utc_datetime, source: :dt)
    field(:contract, :string)
    field(:address, :string, source: :to)
    field(:value, :float)
    field(:sign, :integer)
  end

  @spec changeset(any(), any()) :: no_return()
  def changeset(_, _),
    do: raise("Should not try to change erc20 balances")

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def assets_held_by_address(address) do
    {query, args} = assets_held_by_address_query(address)

    case ClickhouseRepo.query_transform(query, args, & &1) do
      {:ok, contract_value_pairs} ->
        projects =
          contract_value_pairs
          |> Enum.map(fn [contract, _] -> contract end)
          |> Sanbase.Model.Project.List.by_field(:main_contract_address)

        result =
          Enum.map(contract_value_pairs, fn [contract, value] ->
            case Enum.find(projects, &match?(%_{main_contract_address: ^contract}, &1)) do
              nil ->
                nil

              %_{token_decimals: token_decimals, slug: slug} ->
                %{
                  slug: slug,
                  balance: value / Sanbase.Math.ipow(10, token_decimals || 0)
                }
            end
          end)
          |> Enum.reject(&is_nil/1)

        {:ok, result}

      {:error, error} ->
        {:error, error}
    end
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def historical_balance(address, contract, decimals, from, to, interval) do
    pow_decimals = Sanbase.Math.ipow(10, decimals)
    address = String.downcase(address)
    contract = String.downcase(contract)

    {query, args} = historical_balance_query(address, contract, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [dt, value, has_changed] ->
      %{
        datetime: Sanbase.DateTimeUtils.from_erl!(dt),
        balance: value / pow_decimals,
        has_changed: has_changed
      }
    end)
    |> maybe_update_first_balance(fn -> last_balance_before(address, contract, decimals, from) end)
    |> maybe_fill_gaps_last_seen_balance()
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def balance_change([], _, _, _, _), do: {:ok, []}

  def balance_change(addr, contract, token_decimals, from, to) do
    token_decimals = Sanbase.Math.ipow(10, token_decimals)

    query = """
    SELECT
      address,
      argMaxIf(value, dt, dt<=?3 AND sign = 1) AS start_balance,
      argMaxIf(value, dt, dt<=?4 AND sign = 1) AS end_balance,
      end_balance - start_balance AS diff
    FROM #{@table}
    PREWHERE
      address IN (?1) AND
      contract = ?2
    GROUP BY address
    """

    addresses = addr |> List.wrap() |> Enum.map(&String.downcase/1)
    args = [addresses, contract, from, to]

    ClickhouseRepo.query_transform(query, args, fn [address, start_balance, end_balance, change] ->
      {address,
       {start_balance / token_decimals, end_balance / token_decimals, change / token_decimals}}
    end)
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def last_balance_before(address, contract, decimals, datetime) do
    query = """
    SELECT value
    FROM #{@table}
    PREWHERE
      address = ?1 AND
      contract = ?2 AND
      dt <=toDateTime(?3) AND
      sign = 1
    ORDER BY dt DESC
    LIMIT 1
    """

    args = [address, contract, DateTime.to_unix(datetime)]

    case ClickhouseRepo.query_transform(query, args, & &1) do
      {:ok, [[balance]]} -> {:ok, balance / Sanbase.Math.ipow(10, decimals)}
      {:ok, []} -> {:ok, 0}
      {:error, error} -> {:error, error}
    end
  end

  # Private functions

  defp historical_balance_query(address, contract, from, to, interval) do
    interval = Sanbase.DateTimeUtils.str_to_sec(interval)
    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)
    span = div(to_unix - from_unix, interval) |> max(1)

    # The balances table is like a stack. For each balance change there is a record
    # with sign = -1 that is the old balance and with sign = 1 which is the new balance
    query = """
    SELECT time, SUM(value), toUInt8(SUM(has_changed))
      FROM (
        SELECT
          toDateTime(intDiv(toUInt32(?5 + number * ?1), ?1) * ?1) AS time,
          toFloat64(0) AS value,
          toUInt8(0) AS has_changed
        FROM numbers(?2)

    UNION ALL

    SELECT toDateTime(intDiv(toUInt32(dt), ?1) * ?1) AS time, argMax(value, dt), toUInt8(1) AS has_changed
      FROM #{@table}
      PREWHERE
        address = ?3 AND
        contract = ?4 AND
        sign = 1 AND
        dt <= toDateTime(?6)
      GROUP BY time
    )
    GROUP BY time
    ORDER BY time
    """

    args = [interval, span, address, contract, from_unix, to_unix]

    {query, args}
  end

  defp assets_held_by_address_query(address) do
    query = """
    SELECT
      contract,
      argMax(value, blockNumber)
    FROM
      #{@table}
    PREWHERE
      address = ?1 AND
      sign = 1
    GROUP BY contract
    """

    args = [address |> String.downcase()]

    {query, args}
  end
end
