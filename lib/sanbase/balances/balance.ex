defmodule Sanbase.Balance do
  import Sanbase.DateTimeUtils, only: [str_to_sec: 1]

  import Sanbase.Clickhouse.HistoricalBalance.Utils,
    only: [maybe_update_first_balance: 2, maybe_fill_gaps_last_seen_balance: 1]

  alias Sanbase.ClickhouseRepo
  alias Sanbase.Model.Project

  def historical_balance_ohlc(address, slug, from, to, interval) do
    with {:ok, _contract, decimals, infr} <- Project.contract_info_infrastructure_by_slug(slug) do
      blockchain = blockchain_from_infrastructure(infr)
      address = transform_address(address, blockchain)
      do_historical_balance_ohlc(address, slug, decimals, blockchain, from, to, interval)
    end
  end

  def historical_balance(address, slug, from, to, interval) do
    with {:ok, _contract, decimals, infr} <- Project.contract_info_infrastructure_by_slug(slug) do
      blockchain = blockchain_from_infrastructure(infr)

      address = transform_address(address, blockchain)

      do_historical_balance(address, slug, decimals, blockchain, from, to, interval)
    end
  end

  def balance_change(address_or_addresses, slug, from, to) do
    with {:ok, _contract, decimals, infr} <- Project.contract_info_infrastructure_by_slug(slug) do
      blockchain = blockchain_from_infrastructure(infr)
      addresses = List.wrap(address_or_addresses) |> transform_address(blockchain)
      do_balance_change(addresses, slug, decimals, blockchain, from, to)
    end
  end

  def historical_balance_changes(address_or_addresses, slug, from, to, interval) do
    with {:ok, _contract, decimals, infr} <- Project.contract_info_infrastructure_by_slug(slug) do
      blockchain = blockchain_from_infrastructure(infr)
      addresses = List.wrap(address_or_addresses) |> transform_address(blockchain)
      do_historical_balance_changes(addresses, slug, decimals, blockchain, from, to, interval)
    end
  end

  def last_balance_before(address, slug, datetime) do
    with {:ok, _contract, decimals, infr} <- Project.contract_info_infrastructure_by_slug(slug) do
      blockchain = blockchain_from_infrastructure(infr)
      address = transform_address(address, blockchain)
      do_last_balance_before(address, slug, decimals, blockchain, datetime)
    end
  end

  def assets_held_by_address(address) do
    address = transform_address(address, :unknown)
    {query, args} = assets_held_by_address_query(address)

    ClickhouseRepo.query_transform(query, args, fn [slug, balance] ->
      %{
        slug: slug,
        balance: balance
      }
    end)
  end

  def current_balance(address_or_addresses, slug) do
    with {:ok, _contract, decimals, infr} <- Project.contract_info_infrastructure_by_slug(slug) do
      blockchain = blockchain_from_infrastructure(infr)
      addresses = List.wrap(address_or_addresses) |> transform_address(blockchain)
      do_current_balance(addresses, slug, decimals, blockchain)
    end
  end

  # Private functions

  defp do_current_balance(addresses, slug, decimals, blockchain) do
    {query, args} = current_balance_query(addresses, slug, decimals, blockchain)

    ClickhouseRepo.query_transform(query, args, fn [address, balance] ->
      %{
        addresses: address,
        balance: balance
      }
    end)
  end

  defp current_balance_query(addresses, slug, decimals, blockchain) do
    query = """
    SELECT
      address,
      argMax(value, dt) / ?4 AS balance
    FROM (
      SELECT
        address,
        arrayJoin(groupArrayMerge(values)) AS values_merged,
        values_merged.1 AS dt,
        values_merged.2 AS value
      FROM balances_aggregated
      WHERE
        #{address_clause(addresses, argument_position: 1)} AND
        blockchain = ?2 AND
        asset_ref_id = ( SELECT asset_ref_id FROM asset_metadata FINAL WHERE name = ?3 LIMIT 1 )
      GROUP BY address
    )
    GROUP BY address
    """

    args = [addresses, blockchain, slug, Sanbase.Math.ipow(10, decimals)]

    {query, args}
  end

  defp do_balance_change(addresses, slug, decimals, blockchain, from, to) do
    {query, args} = balance_change_query(addresses, slug, decimals, blockchain, from, to)

    ClickhouseRepo.query_transform(query, args, fn
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

  defp balance_change_query(addresses, slug, decimals, blockchain, from, to) do
    query = """
    SELECT
      address,
      argMaxIf(value, dt, dt <= ?4) / ?6 AS start_balance,
      argMaxIf(value, dt, dt <= ?5) / ?6 AS end_balance,
      end_balance - start_balance AS diff
    FROM (
      SELECT
        address,
        arrayJoin(arrayReduce('groupUniqArray', groupArrayMerge(values))) AS values_merged,
        values_merged.1 AS dt,
        values_merged.2 AS value
      FROM balances_aggregated
      WHERE
        #{address_clause(addresses, argument_position: 1)} AND
        blockchain = ?2 AND
        asset_ref_id = ( SELECT asset_ref_id FROM asset_metadata FINAL WHERE name = ?3 LIMIT 1 )
      GROUP BY address, blockchain, asset_ref_id
    )
    GROUP BY address
    """

    args = [
      addresses,
      blockchain,
      slug,
      DateTime.to_unix(from),
      DateTime.to_unix(to),
      Sanbase.Math.ipow(10, decimals)
    ]

    {query, args}
  end

  defp do_historical_balance_changes(addresses, slug, decimals, blockchain, from, to, interval) do
    {query, args} =
      historical_balance_changes_query(addresses, slug, decimals, blockchain, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [unix, balance_change] ->
      %{
        datetime: DateTime.from_unix!(unix),
        balance_change_amount: balance_change
      }
    end)
  end

  defp historical_balance_changes_query(addresses, slug, decimals, blockchain, from, to, interval) do
    interval = Sanbase.DateTimeUtils.str_to_sec(interval)
    to_unix = DateTime.to_unix(to)
    from_unix = DateTime.to_unix(from)
    span = div(to_unix - from_unix, interval) |> max(1)

    balance_changes_query = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(dt), ?1) * ?1) AS time,
      toFloat64(balance_change / ?5) AS balance_change
    FROM (
      SELECT
        dt,
        balance_change
      FROM (
        SELECT
          arraySort(x-> x.1, arrayReduce('groupUniqArray', groupArrayMerge(values))) AS _sorted,
          arrayPushFront(_sorted, tuple(toDateTime(0), toFloat64(0))) AS sorted,
          arrayMap(x-> x.1, sorted) AS dates,
          arrayMap(x-> x.2, sorted) AS balances,
          arrayDifference(balances) AS balance_changes
        FROM balances_aggregated
        WHERE
          #{address_clause(addresses, argument_position: 2)} AND
          blockchain = ?3 AND
          asset_ref_id = (SELECT asset_ref_id FROM asset_metadata FINAL WHERE name = ?4 LIMIT 1)
        GROUP BY address, blockchain, asset_ref_id
      )
      ARRAY JOIN dates AS dt, balance_changes AS balance_change
      WHERE dt >= toDateTime(?6) AND dt < toDateTime(?7)
    )
    """

    query = """
    SELECT time, SUM(balance_change)
      FROM (
        SELECT
          toUnixTimestamp(intDiv(toUInt32(?6 + number * ?1), ?1) * ?1) AS time,
          toFloat64(0) AS balance_change
        FROM numbers(?8)

      UNION ALL

      #{balance_changes_query}
    )
    GROUP BY time
    ORDER BY time
    """

    args = [
      interval,
      addresses,
      blockchain,
      slug,
      Sanbase.Math.ipow(10, decimals),
      from_unix,
      to_unix,
      span
    ]

    {query, args}
  end

  defp do_last_balance_before(address, slug, decimals, blockchain, datetime) do
    {query, args} = last_balance_before_query(address, slug, decimals, blockchain, datetime)

    case ClickhouseRepo.query_transform(query, args, & &1) do
      {:ok, [[balance]]} -> {:ok, balance}
      {:ok, []} -> {:ok, 0}
      {:error, error} -> {:error, error}
    end
  end

  defp last_balance_before_query(address, slug, decimals, blockchain, datetime) do
    query = """
    SELECT
      argMax(value, dt) / ?5 AS last_value_before
    FROM (
      SELECT
        arrayJoin(groupArrayMerge(values)) AS values_merged,
        values_merged.1 AS dt,
        values_merged.2 AS value
      FROM balances_aggregated
      WHERE
        #{address_clause(address, argument_position: 1)} AND
        blockchain = ?2 AND
        asset_ref_id = ( SELECT asset_ref_id FROM asset_metadata FINAL WHERE name = ?3 LIMIT 1 )
      GROUP BY address, blockchain, asset_ref_id
      HAVING dt < toDateTime(?4)
    )
    """

    args = [
      address,
      blockchain,
      slug,
      DateTime.to_unix(datetime),
      Sanbase.Math.ipow(10, decimals)
    ]

    {query, args}
  end

  defp do_historical_balance(address, slug, decimals, blockchain, from, to, interval) do
    {query, args} =
      historical_balance_query(address, slug, decimals, blockchain, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [unix, value, has_changed] ->
      %{
        datetime: DateTime.from_unix!(unix),
        balance: value,
        has_changed: has_changed
      }
    end)
    |> maybe_update_first_balance(fn ->
      do_last_balance_before(address, slug, decimals, blockchain, from)
    end)
    |> maybe_fill_gaps_last_seen_balance()
  end

  defp historical_balance_query(address, slug, decimals, blockchain, from, to, interval) do
    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)
    interval_sec = str_to_sec(interval)
    span = div(to_unix - from_unix, interval_sec) |> max(1)

    query = """
     SELECT time, SUM(value), toUInt8(SUM(has_changed))
      FROM (
        SELECT
          toUnixTimestamp(intDiv(toUInt32(?5 + number * ?1), ?1) * ?1) AS time,
          toFloat64(0) AS value,
          toUInt8(0) AS has_changed
        FROM numbers(?7)

      UNION ALL

      SELECT
        toUnixTimestamp(intDiv(toUInt32(dt), ?1) * ?1) AS time,
        toFloat64(argMax(value, dt)) / ?8 AS value,
        toUInt8(1) AS has_changed
      FROM (
        SELECT
          arrayJoin(groupArrayMerge(values)) AS values_merged,
          values_merged.1 AS dt,
          values_merged.2 AS value
        FROM balances_aggregated
        WHERE
          #{address_clause(address, argument_position: 2)} AND
          blockchain = ?3 AND
          asset_ref_id = ( SELECT asset_ref_id FROM asset_metadata FINAL WHERE name = ?4 LIMIT 1 )
        GROUP BY address, blockchain, asset_ref_id
        HAVING dt >= toDateTime(?5) AND dt < toDateTime(?6)
      )
      GROUP BY time
    )
    GROUP BY time
    ORDER BY time
    """

    args = [
      interval_sec,
      address,
      blockchain,
      slug,
      from_unix,
      to_unix,
      span,
      Sanbase.Math.ipow(10, decimals)
    ]

    {query, args}
  end

  defp do_historical_balance_ohlc(address, slug, decimals, blockchain, from, to, interval) do
    {query, args} =
      historical_balance_ohlc_query(address, slug, decimals, blockchain, from, to, interval)

    ClickhouseRepo.query_transform(
      query,
      args,
      fn [unix, open, high, low, close, has_changed] ->
        %{
          datetime: DateTime.from_unix!(unix),
          open_balance: open,
          high_balance: high,
          low_balance: low,
          close_balance: close,
          has_changed: has_changed
        }
      end
    )
    |> maybe_update_first_balance(fn ->
      do_last_balance_before(address, slug, decimals, blockchain, from)
    end)
    |> maybe_fill_gaps_last_seen_balance()
  end

  defp historical_balance_ohlc_query(address, slug, decimals, blockchain, from, to, interval) do
    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)
    interval_sec = str_to_sec(interval)
    span = div(to_unix - from_unix, interval_sec) |> max(1)

    query = """
    SELECT
      time, SUM(open) AS open,
      SUM(high) AS high,
      SUM(low) AS low,
      SUM(close) AS close,
      toUInt8(SUM(has_changed))
    FROM (
      SELECT
        toUnixTimestamp(intDiv(toUInt32(?5 + number * ?1), ?1) * ?1) AS time,
        toFloat64(0) AS open,
        toFloat64(0) AS high,
        toFloat64(0) AS low,
        toFloat64(0) AS close,
        toUInt8(0) AS has_changed
      FROM numbers(?7)

      UNION ALL

      SELECT
        toUnixTimestamp(intDiv(toUInt32(dt), ?1) * ?1) AS time,
        toFloat64(argMin(value, dt)) / ?8 AS open,
        toFloat64(max(value)) / ?8 AS high,
        toFloat64(min(value)) / ?8 AS low,
        toFloat64(argMax(value, dt)) / ?8 AS close,
        toUInt8(1) AS has_changed
      FROM (
        SELECT
          arrayJoin(groupArrayMerge(values)) AS values_merged,
          values_merged.1 AS dt,
          values_merged.2 AS value
        FROM balances_aggregated
        WHERE
          #{address_clause(address, argument_position: 2)} AND
          blockchain = ?3 AND
          asset_ref_id = ( SELECT asset_ref_id FROM asset_metadata FINAL WHERE name = ?4 LIMIT 1 )
        GROUP BY address, blockchain, asset_ref_id
        HAVING dt >= toDateTime(?5) AND dt < toDateTime(?6)
      )
      GROUP BY time
    )
    GROUP BY time
    ORDER BY time
    """

    args = [
      interval_sec,
      address,
      blockchain,
      slug,
      from_unix,
      to_unix,
      span,
      Sanbase.Math.ipow(10, decimals)
    ]

    {query, args}
  end

  defp assets_held_by_address_query(address) do
    query = """
    SELECT
      name,
      argMax(value, dt) / pow(10, decimals) AS balance
    FROM (
      SELECT
        address,
        asset_ref_id,
        arrayJoin(groupArrayMerge(values)) AS values_merged,
        values_merged.1 AS dt,
        values_merged.2 AS value
      FROM balances_aggregated
      WHERE
        #{address_clause(address, argument_position: 1)} AND
      GROUP BY address, blockchain, asset_ref_id
    )
    INNER JOIN (
      SELECT asset_ref_id, name, decimals
      FROM asset_metadata FINAL
    ) USING (asset_ref_id)
    GROUP BY address, asset_ref_id, name, decimals
    """

    args = [address]

    {query, args}
  end

  defp blockchain_from_infrastructure("ETH"), do: "ethereum"
  defp blockchain_from_infrastructure("BTC"), do: "bitcoin"
  defp blockchain_from_infrastructure("XRP"), do: "ripple"

  defp address_clause(address, opts) when is_binary(address) do
    position = Keyword.fetch!(opts, :argument_position)
    "address = ?#{position}"
  end

  defp address_clause(addresses, opts) when is_list(addresses) do
    position = Keyword.fetch!(opts, :argument_position)
    "address IN (?#{position})"
  end

  defp transform_address("0x" <> _rest = address, :unknown), do: String.downcase(address)
  defp transform_address(address, :unknown) when is_binary(address), do: address

  defp transform_address(addresses, :unknown) when is_list(addresses),
    do: addresses |> List.flatten() |> Enum.map(&transform_address(&1, :unknown))

  defp transform_address(address, "ethereum") when is_binary(address),
    do: String.downcase(address)

  defp transform_address(addresses, "ethereum") when is_list(addresses),
    do: addresses |> List.flatten() |> Enum.map(&String.downcase/1)

  defp transform_address(address, _) when is_binary(address), do: address
  defp transform_address(addresses, _) when is_list(addresses), do: List.flatten(addresses)
end
