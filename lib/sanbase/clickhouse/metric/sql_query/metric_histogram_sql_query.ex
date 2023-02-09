defmodule Sanbase.Clickhouse.MetricAdapter.HistogramSqlQuery do
  import Sanbase.DateTimeUtils, only: [str_to_sec: 1]
  import Sanbase.Metric.SqlQuery.Helper, only: [to_unix_timestamp: 3, dt_to_unix: 2]

  alias Sanbase.Clickhouse.MetricAdapter.FileHandler

  @table_map FileHandler.table_map()
  @name_to_metric_map FileHandler.name_to_metric_map()

  def histogram_data_query("all_spent_coins_cost", slug, _from, to, interval, _limit) do
    interval_sec = interval |> str_to_sec()

    metric =
      case rem(interval_sec, 86_400) do
        0 -> "age_distribution_1day_delta"
        _ -> "age_distribution_5min_delta"
      end

    query = """
    SELECT round(price, 2) AS price, sum(tokens_amount) AS tokens_amount
    FROM (
      SELECT *
      FROM (
        SELECT
            toUnixTimestamp(intDiv(toUInt32(toDateTime(value)), ?3) * ?3) AS t,
            sum(measure) AS tokens_amount
        FROM (
          SELECT dt, argMax(measure, computed_at) AS measure, value
          FROM distribution_deltas_5min
          PREWHERE
            metric_id = ( SELECT argMax(metric_id, computed_at) FROM metric_metadata PREWHERE name = '#{metric}' ) AND
            asset_id = ( SELECT argMax(asset_id, computed_at) FROM asset_metadata PREWHERE name = ?1 ) AND
            dt < toDateTime(?2)
          GROUP BY dt, value
        )
        GROUP BY t
        ORDER BY t ASC
      )
      ALL LEFT JOIN
      (
        SELECT
          toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?3) * ?3) AS t,
          avg(value) AS price
        FROM (
          SELECT dt, argMax(value, computed_at) AS value
          FROM intraday_metrics
          PREWHERE
            asset_id = (SELECT asset_id FROM asset_metadata FINAL PREWHERE name = ?1 LIMIT 1) AND
            metric_id = (SELECT metric_id FROM metric_metadata FINAL PREWHERE name = 'price_usd' LIMIT 1)
          GROUP BY dt
        )
        GROUP BY t
      ) USING (t)
    )
    GROUP BY price
    ORDER BY price ASC
    """

    args = [
      slug,
      to |> DateTime.to_unix(),
      interval_sec
    ]

    {query, args}
  end

  def histogram_data_query(metric, slug, from, to, interval, _limit)
      when metric in ["price_histogram", "spent_coins_cost"] do
    interval_sec = interval |> str_to_sec()

    metric =
      case rem(interval_sec, 86_400) do
        0 -> "age_distribution_1day_delta"
        _ -> "age_distribution_5min_delta"
      end

    query = """
    SELECT round(price, 2) AS price, sum(tokens_amount) AS tokens_amount
    FROM (
      SELECT *
      FROM (
        SELECT
            toUnixTimestamp(intDiv(toUInt32(toDateTime(value)), ?4) * ?4) AS t,
            -sum(measure) AS tokens_amount
        FROM (
          SELECT dt, value, argMax(measure, computed_at) AS measure, value
          FROM distribution_deltas_5min
          PREWHERE
            metric_id = ( SELECT argMax(metric_id, computed_at) FROM metric_metadata PREWHERE name = '#{metric}' ) AND
            asset_id = ( SELECT argMax(asset_id, computed_at) FROM asset_metadata PREWHERE name = ?1 ) AND
            dt >= toDateTime(?2) AND
            dt < toDateTime(?3) AND
            dt != value AND
            value < toDateTime(?2)
          GROUP BY dt, value
          )
        GROUP BY t
        ORDER BY t ASC
      )
      ALL LEFT JOIN
      (
        SELECT
          toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?4) * ?4) AS t,
          avg(value) AS price
        FROM (
          SELECT dt, argMax(value, computed_at) AS value
          FROM intraday_metrics
          PREWHERE
            asset_id = (SELECT asset_id FROM asset_metadata FINAL PREWHERE name = ?1 LIMIT 1) AND
            metric_id = (SELECT metric_id FROM metric_metadata FINAL PREWHERE name = 'price_usd' LIMIT 1)
          GROUP BY dt
        )
        GROUP BY t
      ) USING (t)
    )
    GROUP BY price
    ORDER BY price ASC
    """

    args = [
      slug,
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix(),
      interval_sec
    ]

    {query, args}
  end

  def histogram_data_query("eth2_staked_amount_per_label", "ethereum", from, to, _interval, limit) do
    query = """
    SELECT
      label,
      SUM(locked_sum) AS value
    FROM (
      SELECT
        address,
        locked_sum,
        #{label_select(label_as: "label")}
      FROM (
        SELECT address, SUM(amount) AS locked_sum
        FROM (
            SELECT distinct *
            FROM eth2_staking_transfers_v2 FINAL
            WHERE
              dt < toDateTime(?2)
              #{if from, do: "AND dt >= toDateTime(?3)"}
        )
        GROUP BY address
      )
    )
    GROUP BY label
    ORDER BY value DESC
    LIMIT ?1
    """

    args =
      case from do
        nil -> [limit, to |> DateTime.to_unix()]
        _ -> [limit, to |> DateTime.to_unix(), from |> DateTime.to_unix()]
      end

    {query, args}
  end

  def histogram_data_query(
        "eth2_staked_address_count_per_label",
        "ethereum",
        from,
        to,
        _interval,
        limit
      ) do
    query = """
    SELECT
      label,
      count(address) AS value
    FROM (
      SELECT
        address,
        #{label_select(label_as: "label")}
        FROM (
          SELECT DISTINCT(address)
          FROM eth2_staking_transfers_v2 FINAL
          WHERE
            dt < toDateTime(?2)
            #{if from, do: "AND dt >= toDateTime(?3)"}
        )
    )
    GROUP BY label
    ORDER BY value DESC
    LIMIT ?1
    """

    args =
      case from do
        nil -> [limit, to |> DateTime.to_unix()]
        _ -> [limit, to |> DateTime.to_unix(), from |> DateTime.to_unix()]
      end

    {query, args}
  end

  def histogram_data_query(
        "eth2_unlabeled_staker_inflow_sources",
        "ethereum",
        from,
        to,
        _interval,
        limit
      ) do
    query = """
    SELECT
      label,
      sum(address_inflow) AS value
    FROM (
      SELECT
        address,
        address_inflow,
        #{label_select(label_as: "label", label_str_as: "label_str")}
      FROM (
          SELECT
            from AS address,
            sum(value / 1e18) AS address_inflow
          FROM eth_transfers
          WHERE to GLOBAL IN (
            SELECT address
            FROM (
              SELECT
                address,
                dictGet('default.eth_label_dict', 'labels', (cityHash64(address), toUInt64(0))) AS label_str
              FROM (
                SELECT DISTINCT(address)
                FROM eth2_staking_transfers_v2 FINAL
                WHERE
                  dt < toDateTime(?2)
                  #{if from, do: "AND dt >= toDateTime(?3)"}
              )
            )
            WHERE label_str = ''
          )
        GROUP BY address
      )
    )
    GROUP BY label
    ORDER BY value DESC
    LIMIT ?1
    """

    args =
      case from do
        nil -> [limit, to |> DateTime.to_unix()]
        _ -> [limit, to |> DateTime.to_unix(), from |> DateTime.to_unix()]
      end

    {query, args}
  end

  def histogram_data_query(
        "eth2_top_stakers",
        "ethereum",
        from,
        to,
        _interval,
        limit
      ) do
    query = """
    SELECT
      address,
      label,
      locked_value AS staked
    FROM (
      SELECT
        address,
        locked_value,
        #{label_select(label_as: "label")}
      FROM (
        SELECT
          address,
          SUM(amount) AS locked_value
        FROM eth2_staking_transfers_v2 FINAL
        WHERE
          dt < toDateTime(?2)
          #{if from, do: "AND dt >= toDateTime(?3)"}
        GROUP BY address
        ORDER BY locked_value DESC
        LIMIT ?1
      )
    )
    ORDER BY staked DESC
    """

    args =
      case from do
        nil -> [limit, to |> DateTime.to_unix()]
        _ -> [limit, to |> DateTime.to_unix(), from |> DateTime.to_unix()]
      end

    {query, args}
  end

  def histogram_data_query(
        "eth2_staking_pools",
        "ethereum",
        from,
        to,
        _interval,
        limit
      ) do
    query = """
    SELECT
      label,
      round(sum(locked_sum) / 32) AS value
    FROM
    (
      SELECT
        address,
        SUM(amount) AS locked_sum
      FROM (
        SELECT distinct *
        FROM eth2_staking_transfers_v2 FINAL
        WHERE dt < toDateTime(?2)
        #{if from, do: "AND dt >= toDateTime(?3)"}
      )
      GROUP BY address
    )
    INNER JOIN
    (
      SELECT
        address,
        value AS label
      FROM
      (
        SELECT
          address,
          label_id
        FROM current_label_addresses
        WHERE (blockchain = 'ethereum') AND (label_id IN (
          SELECT label_id
          FROM label_metadata
          WHERE key = 'eth2_staking_address'
        ))
      )
      INNER JOIN
      (
        SELECT
          label_id,
          value
        FROM label_metadata
        WHERE key = 'eth2_staking_address'
      ) USING (label_id)
    ) USING address
    GROUP BY label
    ORDER BY value desc
    LIMIT ?1
    """

    args =
      case from do
        nil -> [limit, to |> DateTime.to_unix()]
        _ -> [limit, to |> DateTime.to_unix(), from |> DateTime.to_unix()]
      end

    {query, args}
  end

  def histogram_data_query(
        "eth2_staking_pools_usd",
        "ethereum",
        from,
        to,
        _interval,
        limit
      ) do
    query = """
    SELECT
      label,
      round(sum(locked_sum)) AS value
    FROM
    (
      SELECT
        address,
        SUM(amount * priceUsd) AS locked_sum
      FROM
      (
        SELECT distinct *
        FROM eth2_staking_transfers_v2 FINAL
        WHERE
          dt < toDateTime(?2)
          #{if from, do: "AND dt >= toDateTime(?3)"}
      ) AS transfers
      INNER JOIN
      (
        SELECT
          dt,
          value AS priceUsd
        FROM intraday_metrics
        FINAL
        WHERE metric_id = get_metric_id('price_usd') AND asset_id = get_asset_id('ethereum')
      ) AS prices
      ON toStartOfFiveMinute(transfers.dt) = prices.dt
      GROUP BY address
    )
    INNER JOIN
    (
      SELECT
        address,
        value AS label
      FROM
      (
        SELECT
            address,
            label_id
        FROM current_label_addresses
        WHERE (blockchain = 'ethereum') AND (label_id IN (
            SELECT label_id
            FROM label_metadata
            WHERE key = 'eth2_staking_address'
        ))
      )
      INNER JOIN
      (
        SELECT
            label_id,
            value
        FROM label_metadata
        WHERE key = 'eth2_staking_address'
      ) USING (label_id)
    ) USING address
    GROUP BY label
    ORDER BY value desc
    LIMIT ?1
    """

    args =
      case from do
        nil -> [limit, to |> DateTime.to_unix()]
        _ -> [limit, to |> DateTime.to_unix(), from |> DateTime.to_unix()]
      end

    {query, args}
  end

  def histogram_data_query(
        "eth2_staking_pools_validators_count_over_time",
        "ethereum",
        from,
        to,
        interval,
        limit
      ) do
    query = """
    WITH (
      SELECT
        groupArray(label) as labels
      FROM
      (
        SELECT
          label,
          sum(locked_sum) AS value
        FROM
        (
          SELECT
              address,
              value AS label
          FROM
          (
              SELECT
                  address,
                  label_id
              FROM current_label_addresses
              WHERE (blockchain = 'ethereum') AND (label_id IN (
                  SELECT label_id
                  FROM label_metadata
                  WHERE key = 'eth2_staking_address'
              ))
          )
          INNER JOIN
          (
              SELECT
                  label_id,
                  value
              FROM label_metadata
              WHERE key = 'eth2_staking_address'
          ) USING (label_id)
        )
        INNER JOIN
        (
          SELECT
              address,
              SUM(amount) AS locked_sum
          FROM
          (
              SELECT DISTINCT *
              FROM eth2_staking_transfers_v2
              FINAL
              WHERE dt < toDateTime(?3)
          )
          GROUP BY address
        ) USING (address)
        GROUP BY label
        ORDER BY value DESC
        LIMIT ?4
      )
    ) AS topStakers
    SELECT
      t,
      groupArr
    FROM
    (
      SELECT
        #{to_unix_timestamp(interval, "dt", argument_position: 1)} AS t,
        groupArray((label, value)) AS groupArr
      FROM (
        SELECT
          dt,
          label,
          value
        FROM (
          SELECT
            label,
            dt,
            SUM(value) OVER (PARTITION BY label ORDER BY dt) AS value
          FROM (
          SELECT
            label,
            dt,
            round(sum(sum_value / 32)) AS value
          FROM (
            SELECT
              label,
              dt,
            sum(sum_value) AS sum_value
            FROM (
              SELECT
                address,
                toDate(dt) as dt,
                sum(amount) AS sum_value
              FROM eth2_staking_transfers_v2 FINAL
              -- ETH2 staking started on 2020-11-03
              WHERE dt >= toDateTime(?2) AND dt < toDateTime(?3)
              GROUP BY address, dt
            ) AS transfers
            INNER JOIN
            (
              SELECT
                address,
                value AS label
              FROM
              (
                SELECT address, label_id
                FROM current_label_addresses
                WHERE (blockchain = 'ethereum') AND (label_id IN ( SELECT label_id FROM label_metadata WHERE key = 'eth2_staking_address' ))
              )
              INNER JOIN
              (
                SELECT label_id, value
                FROM label_metadata
                WHERE key = 'eth2_staking_address' AND has(topStakers, value)
              ) USING (label_id)
            ) USING (address)
            GROUP BY label, dt

            UNION ALL

            SELECT
              DISTINCT value AS label,
              arrayJoin(arrayMap( x -> toDate(x), timeSlots(toDateTime('2020-11-03 00:00:00'), toUInt32(toDateTime(?3) - toIntervalDay(1) - toDateTime('2020-11-03 00:00:00')), toUInt32(?1)))) AS dt,
              0 AS sum_value
            FROM label_metadata FINAL
            WHERE key = 'eth2_staking_address' AND has(topStakers, value)
          )
          GROUP BY label, dt
          )
        )
        WHERE dt >= toDateTime(?2) AND dt < toDateTime(?3)
      )
      GROUP BY dt
      ORDER BY dt ASC
    )
    """

    args = [
      str_to_sec(interval),
      dt_to_unix(:from, from),
      dt_to_unix(:to, to),
      limit
    ]

    {query, args}
  end

  def histogram_data_query(
        "eth2_staking_pools_validators_count_over_time_delta",
        "ethereum",
        from,
        to,
        interval,
        limit
      ) do
    query = """
    SELECT
      t,
      groupArr
    FROM
    (
      SELECT
        #{to_unix_timestamp(interval, "dt", argument_position: 1)} AS t,
        groupArray((label, value)) AS groupArr
      FROM (
        SELECT dt, label, value
        FROM
        (
          SELECT label, dt, round(sum(sum_value / 32)) AS value, rank() OVER (PARTITION BY dt ORDER BY value DESC) AS rank
          FROM (
            SELECT address, toDate(dt) AS dt, sum(amount) AS sum_value
            FROM eth2_staking_transfers_v2 FINAL
            WHERE dt >= toDateTime(?2) AND dt < toDateTime(?3)
            GROUP BY address, dt
          ) AS transfers
          INNER JOIN
          (
            SELECT address, value AS label
            FROM
            (
              SELECT address, label_id
              FROM current_label_addresses
              WHERE (blockchain = 'ethereum') AND (label_id IN ( SELECT label_id FROM label_metadata WHERE key = 'eth2_staking_address' ) )
            )
            INNER JOIN
            (
              SELECT label_id, value
              FROM label_metadata
              WHERE key = 'eth2_staking_address'
            ) USING (label_id)
          ) USING (address)
          GROUP BY label, dt
        )
        WHERE rank <= ?4
      )
      GROUP BY dt
      ORDER BY dt ASC
    )
    """

    args = [
      str_to_sec(interval),
      dt_to_unix(:from, from),
      dt_to_unix(:to, to),
      limit
    ]

    {query, args}
  end

  # Generic
  def histogram_data_query(metric, slug, from, to, interval, limit) do
    query = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(toDateTime(value)), ?5) * ?5) AS t,
      -sum(measure) AS sum_measure
    FROM (
      SELECT value, argMax(measure, computed_at) AS measure
      FROM #{Map.get(@table_map, metric)}
      PREWHERE
        metric_id = ( SELECT argMax(metric_id, computed_at) FROM metric_metadata PREWHERE name = ?1 ) AND
        asset_id = ( SELECT argMax(asset_id, computed_at) FROM asset_metadata PREWHERE name = ?2 ) AND
        dt != value AND
        dt >= toDateTime(?3) AND
        dt < toDateTime(?4) AND
        value < toDateTime(?3)
      GROUP BY dt, value
    )
    GROUP BY t
    ORDER BY sum_measure DESC
    LIMIT ?6
    """

    args = [
      Map.get(@name_to_metric_map, metric),
      slug,
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix(),
      interval |> str_to_sec(),
      limit
    ]

    {query, args}
  end

  defp label_select(opts) do
    label_as = Keyword.get(opts, :label_as, "label")
    label_str_as = Keyword.get(opts, :label_str_as, "label_str")

    """
    dictGet('default.eth_label_dict', 'labels', (cityHash64(address), toUInt64(0))) AS #{label_str_as},
    splitByChar(',', #{label_str_as}) AS label_arr_internal,
    multiIf(
      has(label_arr_internal, 'decentralized_exchange'), 'DEX',
      hasAny(label_arr_internal, ['centralized_exchange', 'deposit']), 'CEX',
      has(label_arr_internal, 'defi'), 'DeFi',
      has(label_arr_internal, 'genesis'), 'Genesis',
      has(label_arr_internal, 'miner'), 'Miner',
      has(label_arr_internal, 'makerdao-cdp-owner'), 'CDP Owner',
      has(label_arr_internal, 'whale'), 'Whale',
      hasAll(label_arr_internal, ['dex_trader', 'withdrawal']), 'CEX & DEX Trader',
      has(label_arr_internal, 'withdrawal'), 'CEX Trader',
      has(label_arr_internal, 'proxy'), 'Proxy',
      has(label_arr_internal, 'dex_trader'), 'DEX Trader',
      #{label_str_as} = '', 'Unlabeled',
      label_arr_internal[1]
      ) AS #{label_as}
    """
  end
end
