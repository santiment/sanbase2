defmodule Sanbase.Clickhouse.HistoricalBalance.Erc20Balance do
  @doc ~s"""
  Module for working with historical ERC20 balances.

  Includes functions for calculating:
  - Historical balances for an address
  - Balance changes for and address
  """
  use Ecto.Schema

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo
  import Sanbase.Clickhouse.HistoricalBalance.Utils

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
    do: raise("Should not try to change eth daily active addresses")

  @doc ~s"""
  Return a list of all assets that the address holds or has held in the past and
  the latest balance
  """
  @spec assets_held_by_address(address) :: {:ok, list(slug_balance_map)} | {:error, String.t()}
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

              %_{token_decimals: token_decimals, coinmarketcap_id: slug} ->
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

  @doc ~s"""
  For a given address or addresses returns the combined balance of tokens
  identified by `contract` for each bucket of size `interval` in the from-to time period
  """
  @spec historical_balance(
          address,
          contract,
          token_decimals,
          DateTime.t(),
          DateTime.t(),
          interval
        ) :: {:ok, list(historical_balance)} | {:error, String.t()}
  def historical_balance(address, contract, token_decimals, from, to, interval) do
    token_decimals = Sanbase.Math.ipow(10, token_decimals)
    address = String.downcase(address)
    contract = String.downcase(contract)

    {query, args} = historical_balance_query(address, contract, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [dt, value, has_changed] ->
      %{
        datetime: Sanbase.DateTimeUtils.from_erl!(dt),
        balance: value / token_decimals,
        has_changed: has_changed
      }
    end)
    |> case do
      {:ok, result} ->
        # Clickhouse fills empty buckets with 0 while we need it filled with the last
        # seen value. As the balance changes happen only when a transfer occurs
        # then we need to fetch the whole history of changes in order to find the balance
        result =
          result
          |> fill_gaps_last_seen_balance()
          |> Enum.drop_while(fn %{datetime: dt} -> DateTime.compare(dt, from) == :lt end)

        {:ok, result}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc ~s"""
  For a given address returns the balance change in tokens, identified by `contract`

  The change is for the from-to period. The returned lists indicates the address,
  before balance, after balance and the balance change
  """
  @spec balance_change(
          address,
          contract,
          token_decimals,
          DateTime.t(),
          DateTime.t()
        ) ::
          {:ok, list({address, {balance_before, balance_after, balance_change}})}
          | {:error, String.t()}
        when balance_before: number(), balance_after: number(), balance_change: number()
  def balance_change(address, contract, token_decimals, from, to) do
    token_decimals = Sanbase.Math.ipow(10, token_decimals)

    query = """
    SELECT
      argMaxIf(value, dt, dt<=?3 AND sign = 1) AS start_balance,
      argMaxIf(value, dt, dt<=?4 AND sign = 1) AS end_balance,
      end_balance - start_balance AS diff
    FROM #{@table}
    PREWHERE
      address = ?1 AND
      contract = ?2
    """

    args = [address |> String.downcase(), contract, from, to]

    ClickhouseRepo.query_transform(query, args, fn [s, e, value] ->
      {s / token_decimals, e / token_decimals, value / token_decimals}
    end)
  end

  # Private functions

  @first_datetime ~N[2015-10-29 00:00:00]
                  |> DateTime.from_naive!("Etc/UTC")
                  |> DateTime.to_unix()
  defp historical_balance_query(address, contract, _from, to, interval) do
    interval = Sanbase.DateTimeUtils.compound_duration_to_seconds(interval)
    to_unix = DateTime.to_unix(to)
    span = div(to_unix - @first_datetime, interval) |> max(1)

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

    args = [interval, span, address, contract, @first_datetime, to_unix]

    {query, args}
  end

  defp assets_held_by_address_query(address) do
    query = """
    SELECT
      contract,
      argMax(value, blockNumber)
    FROM
      erc20_balances
    PREWHERE
      address = ?1 AND
      sign = 1
    GROUP BY contract
    """

    args = [address |> String.downcase()]

    {query, args}
  end
end
