defmodule Sanbase.Clickhouse.MetricAdapter.HistogramSqlQuery do
  import Sanbase.DateTimeUtils, only: [str_to_sec: 1]

  import Sanbase.Metric.SqlQuery.Helper,
    only: [to_unix_timestamp: 3, asset_id_filter: 2, metric_id_filter: 2]

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

    sql = """
    SELECT round(price, 2) AS price, sum(tokens_amount) AS tokens_amount
    FROM (
      SELECT *
      FROM (
        SELECT
          toUnixTimestamp(intDiv(toUInt32(toDateTime(value)), {{interval}}) * {{interval}}) AS t,
          sumKahan(measure) AS tokens_amount
        FROM (
          SELECT dt, argMax(measure, computed_at) AS measure, value
          FROM distribution_deltas_5min
          PREWHERE
            #{metric_id_filter(metric, argument_name: "metric")} AND
            #{asset_id_filter(%{slug: slug}, argument_name: "slug")} AND
            dt < toDateTime({{to}})
          GROUP BY dt, value
        )
        GROUP BY t
        ORDER BY t ASC
      )
      ALL LEFT JOIN
      (
        SELECT
          toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), {{interval}}) * {{interval}}) AS t,
          avg(value) AS price
        FROM (
          SELECT dt, argMax(value, computed_at) AS value
          FROM intraday_metrics
          PREWHERE
            #{metric_id_filter("price_usd", argument_name: "price_metric")} AND
            #{asset_id_filter(%{slug: slug}, argument_name: "slug")} AND
          GROUP BY dt
        )
        GROUP BY t
      ) USING (t)
    )
    GROUP BY price
    ORDER BY price ASC
    """

    params = %{
      slug: slug,
      to: to |> DateTime.to_unix(),
      interval: interval_sec,
      metric: metric,
      price_metric: "price_usd"
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def histogram_data_query(metric, slug, from, to, interval, _limit)
      when metric in ["price_histogram", "spent_coins_cost"] do
    interval_sec = interval |> str_to_sec()

    metric =
      case rem(interval_sec, 86_400) do
        0 -> "age_distribution_1day_delta"
        _ -> "age_distribution_5min_delta"
      end

    sql = """
    SELECT round(price, 2) AS price, sumKahan(tokens_amount) AS tokens_amount
    FROM (
      SELECT *
      FROM (
        SELECT
            toUnixTimestamp(intDiv(toUInt32(toDateTime(value)), {{interval}}) * {{interval}}) AS t,
            -sumKahan(measure) AS tokens_amount
        FROM (
          SELECT dt, value, argMax(measure, computed_at) AS measure, value
          FROM distribution_deltas_5min
          PREWHERE
            #{metric_id_filter(metric, argument_name: "metric")} AND
            #{asset_id_filter(%{slug: slug}, argument_name: "slug")} AND
            dt >= toDateTime({{from}}) AND
            dt < toDateTime({{to}}) AND
            dt != value AND
            value < toDateTime({{from}})
          GROUP BY dt, value
          )
        GROUP BY t
        ORDER BY t ASC
      )
      ALL LEFT JOIN
      (
        SELECT
          toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), {{interval}}) * {{interval}}) AS t,
          avg(value) AS price
        FROM (
          SELECT dt, argMax(value, computed_at) AS value
          FROM intraday_metrics
          PREWHERE
            #{metric_id_filter("price_usd", argument_name: "price_metric")} AND
            #{asset_id_filter(%{slug: slug}, argument_name: "slug")}
          GROUP BY dt
        )
        GROUP BY t
      ) USING (t)
    )
    GROUP BY price
    ORDER BY price ASC
    """

    params = %{
      interval: interval_sec,
      slug: slug,
      from: from |> DateTime.to_unix(),
      to: to |> DateTime.to_unix(),
      metric: metric,
      price_metric: "price_usd"
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def histogram_data_query("eth2_staked_amount_per_label", "ethereum", from, to, _interval, limit) do
    sql = """
    SELECT
      label,
      sumKahan(locked_sum) AS value
    FROM (
      SELECT
        address,
        locked_sum,
        #{label_select(label_as: "label")}
      FROM (
        SELECT address, sumKahan(amount) AS locked_sum
        FROM (
            SELECT DISTINCT *
            FROM eth2_staking_transfers_v2 FINAL
            WHERE
              dt < toDateTime({{to}})
              #{if from, do: "AND dt >= toDateTime({{from}})"}
        )
        GROUP BY address
      )
    )
    GROUP BY label
    ORDER BY value DESC
    LIMIT {{limit}}
    """

    params = %{
      limit: limit,
      from: from && from |> DateTime.to_unix(),
      to: to |> DateTime.to_unix()
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def histogram_data_query(
        "eth2_staked_address_count_per_label",
        "ethereum",
        from,
        to,
        _interval,
        limit
      ) do
    sql = """
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
            dt < toDateTime({{to}})
            #{if from, do: "AND dt >= toDateTime({{from}})"}
        )
    )
    GROUP BY label
    ORDER BY value DESC
    LIMIT {{limit}}
    """

    params = %{
      limit: limit,
      from: from && from |> DateTime.to_unix(),
      to: to |> DateTime.to_unix()
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def histogram_data_query(
        "eth2_unlabeled_staker_inflow_sources",
        "ethereum",
        from,
        to,
        _interval,
        limit
      ) do
    sql = """
    SELECT
      label,
      sumKahan(address_inflow) AS value
    FROM (
      SELECT
        address,
        address_inflow,
        #{label_select(label_as: "label", label_str_as: "label_str")}
      FROM (
          SELECT
            from AS address,
            sumKahan(value / 1e18) AS address_inflow
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
                  dt < toDateTime({{to}})
                  #{if from, do: "AND dt >= toDateTime({{from}})"}
              )
            )
            WHERE label_str = ''
          )
        GROUP BY address
      )
    )
    GROUP BY label
    ORDER BY value DESC
    LIMIT {{limit}}
    """

    params = %{
      from: from && from |> DateTime.to_unix(),
      to: to |> DateTime.to_unix(),
      limit: limit
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def histogram_data_query(
        "eth2_top_stakers",
        "ethereum",
        from,
        to,
        _interval,
        limit
      ) do
    sql = """
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
          dt < toDateTime({{to}})
          #{if from, do: "AND dt >= toDateTime({{from}})"}
        GROUP BY address
        ORDER BY locked_value DESC
        LIMIT {{limit}}
      )
    )
    ORDER BY staked DESC
    """

    params = %{
      from: from && from |> DateTime.to_unix(),
      to: to |> DateTime.to_unix(),
      limit: limit
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def histogram_data_query(
        "eth2_staking_pools",
        "ethereum",
        from,
        to,
        _interval,
        limit
      ) do
    sql = """
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
        WHERE dt < toDateTime({{to}})
        #{if from, do: "AND dt >= toDateTime({{from}})"}
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
          WHERE key = 'eth2_staking_name'
        ))
      )
      INNER JOIN
      (
        SELECT
          label_id,
          value
        FROM label_metadata
        WHERE key = 'eth2_staking_name'
      ) USING (label_id)
    ) USING address
    GROUP BY label
    ORDER BY value desc
    LIMIT {{limit}}
    """

    params = %{
      from: from && from |> DateTime.to_unix(),
      to: to |> DateTime.to_unix(),
      limit: limit
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def histogram_data_query(
        "eth2_staking_pools_usd",
        "ethereum",
        from,
        to,
        _interval,
        limit
      ) do
    sql = """
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
          dt < toDateTime({{to}})
          #{if from, do: "AND dt >= toDateTime({{from}})"}
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
            WHERE key = 'eth2_staking_name'
        ))
      )
      INNER JOIN
      (
        SELECT
            label_id,
            value
        FROM label_metadata
        WHERE key = 'eth2_staking_name'
      ) USING (label_id)
    ) USING address
    GROUP BY label
    ORDER BY value desc
    LIMIT {{limit}}
    """

    params = %{
      from: from && from |> DateTime.to_unix(),
      to: to |> DateTime.to_unix(),
      limit: limit
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def histogram_data_query(
        "eth2_staking_pools_validators_count_over_time",
        "ethereum",
        from,
        to,
        interval,
        limit
      ) do
    sql = """
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
                  WHERE key = 'eth2_staking_name'
              ))
          )
          INNER JOIN
          (
              SELECT
                  label_id,
                  value
              FROM label_metadata
              WHERE key = 'eth2_staking_name'
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
              WHERE dt < toDateTime({{to}})
          )
          GROUP BY address
        ) USING (address)
        GROUP BY label
        ORDER BY value DESC
        LIMIT {{limit}}
      )
    ) AS topStakers
    SELECT
      t,
      groupArr
    FROM
    (
      SELECT
        #{to_unix_timestamp(interval, "dt", argument_name: "interval")} AS t,
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
              WHERE dt >= toDateTime({{from}}) AND dt < toDateTime({{to}})
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
                WHERE (blockchain = 'ethereum') AND (label_id IN ( SELECT label_id FROM label_metadata WHERE key = 'eth2_staking_name' ))
              )
              INNER JOIN
              (
                SELECT label_id, value
                FROM label_metadata
                WHERE key = 'eth2_staking_name' AND has(topStakers, value)
              ) USING (label_id)
            ) USING (address)
            GROUP BY label, dt

            UNION ALL

            SELECT
              DISTINCT value AS label,
              arrayJoin(arrayMap( x -> toDate(x), timeSlots(toDateTime('2020-11-03 00:00:00'), toUInt32(toDateTime({{to}}) - toIntervalDay(1) - toDateTime('2020-11-03 00:00:00')), toUInt32({{interval}})))) AS dt,
              0 AS sum_value
            FROM label_metadata FINAL
            WHERE key = 'eth2_staking_name' AND has(topStakers, value)
          )
          GROUP BY label, dt
          )
        )
        WHERE dt >= toDateTime({{from}}) AND dt < toDateTime({{to}})
      )
      GROUP BY dt
      ORDER BY dt ASC
    )
    """

    params = %{
      interval: str_to_sec(interval),
      from: from |> DateTime.to_unix(),
      to: to |> DateTime.to_unix(),
      limit: limit
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def histogram_data_query(
        "eth2_staking_pools_validators_count_over_time_delta",
        "ethereum",
        from,
        to,
        interval,
        limit
      ) do
    sql = """
    SELECT
      t,
      groupArr
    FROM
    (
      SELECT
        #{to_unix_timestamp(interval, "dt", argument_name: "interval")} AS t,
        groupArray((label, value)) AS groupArr
      FROM (
        SELECT dt, label, value
        FROM
        (
          SELECT label, dt, round(sum(sum_value / 32)) AS value, rank() OVER (PARTITION BY dt ORDER BY value DESC) AS rank
          FROM (
            SELECT address, toDate(dt) AS dt, sum(amount) AS sum_value
            FROM eth2_staking_transfers_v2 FINAL
            WHERE dt >= toDateTime({{from}}) AND dt < toDateTime({{to}})
            GROUP BY address, dt
          ) AS transfers
          INNER JOIN
          (
            SELECT address, value AS label
            FROM
            (
              SELECT address, label_id
              FROM current_label_addresses
              WHERE (blockchain = 'ethereum') AND (label_id IN ( SELECT label_id FROM label_metadata WHERE key = 'eth2_staking_name' ) )
            )
            INNER JOIN
            (
              SELECT label_id, value
              FROM label_metadata
              WHERE key = 'eth2_staking_name'
            ) USING (label_id)
          ) USING (address)
          GROUP BY label, dt
        )
        WHERE rank <= {{limit}}
      )
      GROUP BY dt
      ORDER BY dt ASC
    )
    """

    params = %{
      interval: str_to_sec(interval),
      from: from |> DateTime.to_unix(),
      to: to |> DateTime.to_unix(),
      limit: limit
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  # Generic, "age_distribution" goes here
  def histogram_data_query(metric, slug, from, to, interval, limit) do
    sql = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(toDateTime(value)), {{interval}}) * {{interval}}) AS t,
      -sum(measure) AS sum_measure
    FROM (
      SELECT value, argMax(measure, computed_at) AS measure
      FROM #{Map.get(@table_map, metric)}
      PREWHERE
        #{metric_id_filter(metric, argument_name: "metric")} AND
        #{asset_id_filter(%{slug: slug}, argument_name: "slug")} AND
        dt != value AND
        dt >= toDateTime({{from}}) AND
        dt < toDateTime({{to}}) AND
        value < toDateTime({{from}})
      GROUP BY dt, value
    )
    GROUP BY t
    ORDER BY sum_measure DESC
    LIMIT {{limit}}
    """

    params = %{
      slug: slug,
      metric: Map.get(@name_to_metric_map, metric),
      interval: str_to_sec(interval),
      from: from |> DateTime.to_unix(),
      to: to |> DateTime.to_unix(),
      limit: limit
    }

    Sanbase.Clickhouse.Query.new(sql, params)
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
