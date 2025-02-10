defmodule Sanbase.Clickhouse.TopHolders do
  @moduledoc ~s"""
  Uses ClickHouse to calculate the percent supply in exchanges, non exchanges and combined
  """

  import Sanbase.DateTimeUtils, only: [str_to_sec: 1]
  import Sanbase.Metric.SqlQuery.Helper
  import Sanbase.Utils.Transform, only: [opts_to_limit_offset: 1]

  alias Sanbase.Clickhouse.Label
  alias Sanbase.Clickhouse.Query
  alias Sanbase.ClickhouseRepo
  alias Sanbase.Project

  @eth_table "eth_top_holders_daily"
  @erc20_table "erc20_top_holders_daily"

  @type percent_of_total_supply :: %{
          datetime: DateTime.t(),
          in_exchanges: number(),
          outside_exchanges: number(),
          in_top_holders_total: number()
        }

  @type top_holders :: %{
          datetime: DateTime.t(),
          address: String.t(),
          value: number(),
          value_usd: number(),
          part_of_total: number()
        }

  def realtime_top_holders(slug, opts) do
    query_struct = realtime_top_holders_query(slug, opts)

    ClickhouseRepo.query_transform(query_struct, &holder_transform_func/1)
  end

  @spec top_holders(String.t(), DateTime.t(), DateTime.t(), Keyword.t()) ::
          {:ok, list(top_holders)} | {:error, String.t()}
  def top_holders(slug, from, to, opts) do
    contract_opts = [contract_type: :latest_onchain_contract]

    with {:ok, contract, decimals} <-
           Project.contract_info_by_slug(slug, contract_opts),
         query_struct =
           top_holders_query(slug, contract, decimals, from, to, opts),
         {:ok, result} <-
           ClickhouseRepo.query_transform(
             query_struct,
             &holder_transform_func/1
           ),
         addresses = result |> Enum.map(& &1.address) |> Enum.uniq(),
         {:ok, address_labels_map} <- Label.get_address_labels(slug, addresses) do
      labelled_top_holders =
        Enum.map(result, fn top_holder ->
          labels = Map.get(address_labels_map, top_holder.address, [])
          Map.put(top_holder, :labels, labels)
        end)

      {:ok, labelled_top_holders}
    end
  end

  @spec percent_of_total_supply(
          String.t(),
          non_neg_integer(),
          DateTime.t(),
          DateTime.t(),
          String.t()
        ) :: {:ok, list(percent_of_total_supply)} | {:error, String.t()}
  def percent_of_total_supply(slug, holders_count, from, to, interval) do
    contract_opts = [contract_type: :latest_onchain_contract]

    with {:ok, contract, decimals} <-
           Project.contract_info_by_slug(slug, contract_opts) do
      query_struct =
        percent_of_total_supply_query(
          contract,
          decimals,
          holders_count,
          from,
          to,
          interval
        )

      ClickhouseRepo.query_transform(
        query_struct,
        fn [dt, in_exchanges, outside_exchanges, in_top_holders_total] ->
          %{
            datetime: DateTime.from_unix!(dt),
            in_exchanges: in_exchanges,
            outside_exchanges: outside_exchanges,
            in_top_holders_total: in_top_holders_total
          }
        end
      )
    end
  end

  @spec percent_of_total_supply(
          contract :: String.t(),
          decimals :: non_neg_integer(),
          number_of_top_holders :: non_neg_integer(),
          from :: DateTime.t(),
          to :: DateTime.t(),
          interval :: String.t()
        ) :: {:ok, list(percent_of_total_supply)} | {:error, String.t()}
  def percent_of_total_supply(contract, decimals, number_of_holders, from, to, interval) do
    query_struct =
      percent_of_total_supply_query(
        contract,
        decimals,
        number_of_holders,
        from,
        to,
        interval
      )

    ClickhouseRepo.query_transform(
      query_struct,
      fn [dt, in_exchanges, outside_exchanges, in_holders] ->
        %{
          datetime: DateTime.from_unix!(dt),
          in_exchanges: in_exchanges,
          outside_exchanges: outside_exchanges,
          in_top_holders_total: in_holders
        }
      end
    )
  end

  # helpers

  defp holder_transform_func([dt, address, value, value_usd, part_of_total]) do
    %{
      datetime: DateTime.from_unix!(dt),
      address: address,
      value: value,
      value_usd: value_usd,
      part_of_total: part_of_total
    }
  end

  defp realtime_top_holders_query("ethereum" = slug, opts) do
    {limit, offset} = opts_to_limit_offset(opts)

    sql = """
    WITH
      ( SELECT argMax(balance, dt) FROM eth_balances_realtime total_balance,
      ( SELECT pow(10, decimals) FROM asset_metadata FINAL where name = {{slug}} LIMIT 1 ) AS decimals,
      ( SELECT argMax(value, dt)
        FROM intraday_metrics
        WHERE #{asset_id_filter(%{slug: slug}, argument_name: "slug")} AND #{metric_id_filter("price_usd", argument_name: "metric")}
      ) AS price_usd

    SELECT
      toUnixTimestamp(max(dt)),
      address,
      (argMax(balance, dt) / decimals) AS balance2,
      balance2 * price_usd AS balance_usd,
      (balance2 / (total_balance / decimals)) AS partOfTotal
    FROM eth_balances_realtime
    WHERE
      addressType = 'normal'
    GROUP BY address
    ORDER BY balance2 DESC
    LIMIT {{limit}} OFFSET {{ofset}}
    """

    params = %{
      slug: slug,
      metric: "price_usd",
      limit: limit,
      offset: offset
    }

    Query.new(sql, params)
  end

  defp realtime_top_holders_query(slug, opts) do
    asset_ref_id_filter = fn column, opts ->
      arg_name = Keyword.fetch!(opts, :argument_name)

      "asset_ref_id = ( SELECT #{column} FROM asset_metadata FINAL WHERE name = {{#{arg_name}}} LIMIT 1 )"
    end

    sql = """
    WITH
      (
        SELECT argMax(balance, dt)
        FROM erc20_balances_realtime
        WHERE
          #{asset_ref_id_filter.("asset_ref_id", argument_name: "slug")} AND
          addressType = 'total'
      ) AS total_balance,
      (
        SELECT pow(10, decimals)
        FROM asset_metadata FINAL
        WHERE name = {{slug}} LIMIT 1
      ) AS decimals,
      (
        SELECT argMax(value, dt)
        FROM intraday_metrics
        WHERE
          #{asset_id_filter(%{slug: slug}, argument_name: "slug")} AND
          #{metric_id_filter("price_usd", argument_name: "metric")}
      ) AS price_usd

    SELECT
      toUnixTimestamp(max(dt)),
      address,
      (argMax(balance, dt) / decimals) AS balance2,
      balance2 * price_usd AS balance_usd,
      (balance2 / (total_balance / decimals)) AS partOfTotal
    FROM erc20_balances_realtime
    WHERE
      #{asset_ref_id_filter.("asset_ref_id", argument_name: "slug")} AND
      addressType = 'normal'
    GROUP BY address
    ORDER BY balance2 DESC
    LIMIT {{limit}} OFFSET {{offset}}
    """

    {limit, offset} = opts_to_limit_offset(opts)

    params = %{slug: slug, metric: "price_usd", limit: limit, offset: offset}

    Query.new(sql, params)
  end

  defp top_holders_query(slug, contract, decimals, from, to, opts) do
    {limit, offset} = opts_to_limit_offset(opts)

    params = %{
      slug: slug,
      contract: contract,
      decimals: decimals,
      from: DateTime.to_unix(from),
      to: DateTime.to_unix(to),
      limit: limit,
      offset: offset,
      price_usd_metric: "price_usd"
    }

    {labels_owners_filter, params} = maybe_add_labels_owners_filter(opts, params)

    table = if slug == "ethereum", do: @eth_table, else: @erc20_table

    # Select the raw data and combine it with the partOfTotal by a UNION
    inner_sql = """
    SELECT
      dt, contract, address, rank, value / pow(10, {{decimals}}) AS value,
      multiIf(valueTotal > 0, value / (valueTotal / pow(10, {{decimals}})), 0) AS partOfTotal
    FROM (
      SELECT *
      FROM #{table} FINAL
      WHERE
        contract = {{contract}}
        AND rank > 0
        AND address NOT IN ('TOTAL', 'freeze')
        AND dt >= toStartOfDay(toDateTime({{from}}))
        AND dt <= toStartOfDay(toDateTime({{to}}))
    )
    GLOBAL ANY LEFT JOIN (
      SELECT
        dt,
        sum(value) AS valueTotal
      FROM #{table} FINAL
      WHERE
        contract = {{contract}}
        AND address IN ('TOTAL','freeze') AND rank < 0
        AND dt >= toStartOfDay(toDateTime({{from}}))
        AND dt <= toStartOfDay(toDateTime({{to}}))
      GROUP BY dt
    ) USING (dt)
    """

    # Order the data by value in descending order and select one row per address
    top_addresses_sql = """
    SELECT
      max(dt) AS dtMax, address, argMax(value, dt) AS val, argMax(partOfTotal, dt) AS partOfTotal
    FROM ( #{inner_sql} )
    GROUP BY address
    ORDER BY val DESC
    """

    # Apply (maybe) the filtering by labels and add the pagination - limit and offset
    filter_labels_sql = """
    SELECT
      dtMax AS dt, address, val, partOfTotal
    FROM ( #{top_addresses_sql} )
    #{labels_owners_filter}
    LIMIT {{limit}} OFFSET {{offset}}
    """

    # Join with the intraday_metrics table to fetch the price_usd and add the value_usd
    sql = """
    SELECT
      toUnixTimestamp(dt), address, val AS value, val * price AS value_usd, partOfTotal
    FROM ( #{filter_labels_sql} )
    GLOBAL ANY JOIN (
      SELECT
        toStartOfDay(dt) AS dt,
        avg(value) AS price
      FROM intraday_metrics FINAL
      WHERE
        #{metric_id_filter("price_usd", argument_name: "price_usd_metric")} AND
        #{asset_id_filter(%{slug: slug}, argument_name: "slug")}
      GROUP BY dt
    ) USING (dt)
    """

    Query.new(sql, params)
  end

  defp maybe_add_labels_owners_filter(opts, params) do
    {owners_str, params} = filter_str(:owners, opts, params)
    {labels_str, params} = filter_str(:labels, opts, params)

    if labels_str == nil and owners_str == nil do
      {"", params}
    else
      clause =
        [labels_str, owners_str]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" AND ")

      str = """
      GLOBAL ANY INNER JOIN
      (
        SELECT address
        FROM current_label_addresses
        WHERE blockchain = 'ethereum' AND label_id IN (SELECT label_id FROM label_metadata WHERE #{clause})
      ) USING (address)
      """

      {str, params}
    end
  end

  defp filter_str(:owners, opts, params) do
    case Keyword.get(opts, :owners, :all) do
      :all ->
        {nil, params}

      values ->
        params_count = map_size(params)
        owners_key = "owners_param_count_#{params_count}"
        str = "(key = 'owner' AND value IN ({{#{owners_key}}}))"

        {str, Map.put(params, owners_key, values)}
    end
  end

  defp filter_str(:labels, opts, params) do
    case Keyword.get(opts, :labels, :all) do
      :all ->
        {nil, params}

      values ->
        params_count = map_size(params)
        labels_key = "labels_param_count_#{params_count}"
        str = "(key IN ({{#{labels_key}}}))"

        {str, Map.put(params, labels_key, values)}
    end
  end

  defp percent_of_total_supply_query(contract, decimals, number_of_holders, from, to, interval) do
    table = if contract == "ETH", do: @eth_table, else: @erc20_table

    sql = """
    SELECT
      #{to_unix_timestamp(interval, "dt", argument_name: "interval")} AS time,
      sumIf(partOfTotal, isExchange = 1) * 100 AS in_exchanges,
      sumIf(partOfTotal, isExchange = 0) * 100 AS outside_exchanges,
      in_exchanges + outside_exchanges AS in_top_holders_total
    FROM
    (
      SELECT dt, contract, address, rank, value, partOfTotal
      FROM
      (
        SELECT *
        FROM
        (
          SELECT dt, contract, address, rank, value, partOfTotal FROM
          (
            SELECT
              dt,
              contract,
              address,
              rank,
              value / pow(10, {{decimals}}) AS value,
              multiIf(valueTotal > 0, value / (valueTotal / pow(10, {{decimals}})), 0) AS partOfTotal
            FROM
            (
              SELECT *
              FROM #{table}
              WHERE
                contract = {{contract}} AND
                rank > 0 AND
                rank <= {{number_of_holders}} AND
                dt >= toStartOfDay(toDateTime({{from}})) AND
                dt <= toStartOfDay(toDateTime({{to}}))
            )
            GLOBAL ANY LEFT JOIN
            (
              SELECT
                dt,
                sum(value) AS valueTotal
              FROM #{table}
              WHERE
                contract = {{contract}} AND
                address IN ('TOTAL', 'freeze') AND rank < 0 AND
                dt >= toStartOfDay(toDateTime({{from}})) AND
                dt <= toStartOfDay(toDateTime({{to}}))
              GROUP BY dt
            ) USING (dt)
          )
        )
      )
    )
    GLOBAL ANY LEFT JOIN
    (
      SELECT
        address,
        1 AS isExchange
      FROM current_label_addresses
      WHERE blockchain = 'ethereum' AND label_id IN (SELECT label_id FROM label_metadata WHERE key IN ('centralized_exchange', 'decentralized_exchange'))
    ) USING (address)
    GROUP BY dt
    ORDER BY dt ASC
    """

    params = %{
      decimals: decimals,
      contract: contract,
      number_of_holders: number_of_holders,
      from: DateTime.to_unix(from),
      to: DateTime.to_unix(to),
      interval: str_to_sec(interval)
    }

    Query.new(sql, params)
  end
end
