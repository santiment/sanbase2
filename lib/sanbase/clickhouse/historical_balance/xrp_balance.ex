defmodule Sanbase.Clickhouse.HistoricalBalance.XrpBalance do
  @doc ~s"""
  Module for working with historical XRP balances.
  """

  @behaviour Sanbase.Clickhouse.HistoricalBalance.Behaviour

  import Sanbase.Clickhouse.HistoricalBalance.Utils
  import Sanbase.Metric.SqlQuery.Helper, only: [timerange_parameters: 3]

  alias Sanbase.ClickhouseRepo

  @table "xrp_balances"

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def assets_held_by_address(address) do
    query_struct = current_balances_query([address], "XRP")

    ClickhouseRepo.query_transform(query_struct, fn [^address, value] ->
      %{
        slug: "xrp",
        balance: value
      }
    end)
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def current_balance(addresses, _currency, _decimals) do
    query_struct = current_balances_query(addresses, "XRP")

    ClickhouseRepo.query_transform(query_struct, fn [address, value] ->
      %{
        address: address,
        balance: value
      }
    end)
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def historical_balance([], _, _, _, _, _), do: {:ok, []}

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def historical_balance(
        addresses,
        %{currency: _, issuer: _} = target_map,
        decimals,
        from,
        to,
        interval
      )
      when is_list(addresses) do
    combine_historical_balances(addresses, fn address ->
      historical_balance(address, target_map, decimals, from, to, interval)
    end)
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def historical_balance(
        address,
        %{currency: currency, issuer: issuer},
        _decimals,
        from,
        to,
        interval
      )
      when is_binary(address) do
    query_struct = historical_balance_query(address, currency, issuer, from, to, interval)

    ClickhouseRepo.query_transform(query_struct, fn [dt, balance, has_changed] ->
      %{
        datetime: DateTime.from_unix!(dt),
        balance: balance,
        has_changed: has_changed
      }
    end)
    |> maybe_update_first_balance(fn ->
      last_balance_before(address, %{currency: currency, issuer: issuer}, 0, from)
    end)
    |> maybe_fill_gaps_last_seen_balance()
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def balance_change([], _, _, _, _), do: {:ok, []}

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def balance_change(
        address_or_addresses,
        %{currency: currency, issuer: issuer},
        _decimals,
        from,
        to
      )
      when is_binary(address_or_addresses) or is_list(address_or_addresses) do
    query_struct = balance_change_query(address_or_addresses, currency, issuer, from, to)

    ClickhouseRepo.query_transform(query_struct, fn
      [address, balance_start, balance_end, balance_change] ->
        %{
          address: address,
          balance_start: balance_start,
          balance_end: balance_end,
          balance_change_amount: balance_change,
          balance_change_percent: Sanbase.Math.percent_change(balance_start, balance_end)
        }
    end)
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def historical_balance_change([], _, _, _, _, _), do: {:ok, []}

  def historical_balance_change(
        address_or_addresses,
        %{currency: currency, issuer: issuer},
        _decimals,
        from,
        to,
        interval
      )
      when is_binary(address_or_addresses) or is_list(address_or_addresses) do
    query_struct =
      historical_balance_change_query(
        address_or_addresses,
        currency,
        issuer,
        from,
        to,
        interval
      )

    ClickhouseRepo.query_transform(query_struct, fn [dt, change] ->
      %{
        datetime: DateTime.from_unix!(dt),
        balance_change: change
      }
    end)
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def last_balance_before(address, %{currency: currency, issuer: issuer}, _decimals, datetime) do
    query_struct = last_balance_before_query(address, currency, issuer, datetime)

    case ClickhouseRepo.query_transform(query_struct, & &1) do
      {:ok, [[balance]]} -> {:ok, balance}
      {:ok, []} -> {:ok, 0}
      {:error, error} -> {:error, error}
    end
  end

  # Private functions

  defp last_balance_before_query(address, currency, issuer, datetime) do
    sql = """
    SELECT balance
    FROM #{@table}
    PREWHERE
      address = {{address}} AND
      currency = {{currency}} AND
      issuerCurrency = {{issuer_currency}} AND
      dt <= toDateTime({{datetime}}) AND
      dt >= toDateTime({{datetime}}) - INTERVAL 3 YEAR
    ORDER BY dt DESC
    LIMIT 1
    """

    params = %{
      address: address,
      currency: currency,
      datetime: DateTime.to_unix(datetime),
      issuer_currency: get_issuer_currency(issuer, currency)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp current_balances_query(address, currency) do
    sql = """
    SELECT address, argMax(value, dt)
    FROM #{@table}
    PREWHERE
      address = {{address}} AND
      currency = {{currency}} AND
      sign = 1
    GROUP BY address
    """

    params = %{
      address: address,
      currency: currency
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp historical_balance_query(address, currency, issuer, from, to, interval)
       when is_binary(address) do
    # The balances table is like a stack. For each balance change there is a record
    # with sign = -1 that is the old balance and with sign = 1 which is the new balance
    sql = """
    SELECT time, SUM(balance), toUInt8(SUM(has_changed))
      FROM (
        SELECT
          toUnixTimestamp(intDiv(toUInt32({{from}} + number * {{interval}}), {{interval}}) * {{interval}}) AS time,
          toFloat64(0) AS balance,
          toInt8(0) AS has_changed
        FROM numbers({{span}})

      UNION ALL

      SELECT
        toUnixTimestamp(intDiv(toUInt32(dt), {{interval}}) * {{interval}}) AS time,
        argMax(balance, dt) AS balance,
        toUInt8(1) AS has_changed
      FROM #{@table}
      PREWHERE
        address = {{address}} AND
        dt >= toDateTime({{from}}) AND
        dt < toDateTime({{to}}) AND
        currency = {{currency}} AND
        assetRefId = cityHash64('XRP_' || {{issuer_currency}})
      GROUP BY time
    )
    GROUP BY time
    ORDER BY time
    """

    {from, to, interval, span} = timerange_parameters(from, to, interval)

    params = %{
      interval: interval,
      span: span,
      address: address,
      from: from,
      to: to,
      currency: currency,
      issuer_currency: get_issuer_currency(issuer, currency)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp balance_change_query(address_or_addresses, currency, issuer, from, to) do
    sql = """
    SELECT
      address,
      argMaxIf(balance, dt, dt <= {{from}}) AS start_balance,
      argMaxIf(balance, dt, dt <= {{to}}) AS end_balance,
      end_balance - start_balance AS diff
    FROM #{@table}
    PREWHERE
      address IN ({{addresses}}) AND
      currency = {{currency}} AND
      assetRefId = cityHash64('XRP_' || {{issuer_currency}})
    GROUP BY address
    """

    params = %{
      addresses: address_or_addresses |> List.wrap() |> List.flatten(),
      currency: currency,
      issuer_currency: get_issuer_currency(issuer, currency),
      from: from,
      to: to
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp historical_balance_change_query(
         address_or_addresses,
         currency,
         issuer,
         from,
         to,
         interval
       ) do
    # The balances table is like a stack. For each balance change there is a record
    # with sign = -1 that is the old balance and with sign = 1 which is the new balance
    sql = """
    SELECT time, SUM(change)
      FROM (
        SELECT
          toUnixTimestamp(intDiv(toUInt32({{from}} + number * {{interval}}), {{interval}}) * {{interval}}) AS time,
          toFloat64(0) AS change
        FROM numbers({{span}})

      UNION ALL

      SELECT
        toUnixTimestamp(intDiv(toUInt32(dt), {{interval}}) * {{interval}}) AS time,
        any(change) AS change
      FROM (
        SELECT dt, assetRefId, address, blockNumber, transactionIndex, (balance - oldBalance) AS change
        FROM xrp_balances
        PREWHERE
          address IN ({addresses}) AND
          currency = {{currency}} AND
          assetRefId = cityHash64('XRP_' || {{issuer_currency}}) AND
          dt >= toDateTime({{from}}) AND
          dt <= toDateTime({{to}})
      )
      GROUP BY assetRefId, address, dt, blockNumber, transactionIndex
    )
    GROUP BY time
    ORDER BY time
    """

    {from, to, interval, span} = timerange_parameters(from, to, interval)

    params = %{
      addresses: address_or_addresses |> List.wrap() |> List.flatten(),
      interval: interval,
      span: span,
      currency: currency,
      issuer_currency: get_issuer_currency(issuer, currency),
      from: from,
      to: to
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp get_issuer_currency("XRP", "XRP"), do: "XRP"
  defp get_issuer_currency(issuer, currency), do: "#{issuer}/#{currency}}"
end
