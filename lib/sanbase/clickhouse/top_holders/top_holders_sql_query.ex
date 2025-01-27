defmodule Sanbase.Clickhouse.TopHolders.SqlQuery do
  @moduledoc false

  import Sanbase.Metric.SqlQuery.Helper,
    only: [
      timerange_parameters: 3,
      to_unix_timestamp_from_number: 2,
      to_unix_timestamp: 3,
      aggregation: 3
    ]

  defguard has_labels(map)
           when (is_map_key(map, :include_labels) and
                   is_list(:erlang.map_get(:include_labels, map)) and
                   length(:erlang.map_get(:include_labels, map)) > 0) or
                  (is_map_key(map, :exclude_labels) and
                     is_list(:erlang.map_get(:exclude_labels, map)) and
                     length(:erlang.map_get(:exclude_labels, map)) > 0)

  def timeseries_data_query("amount_in_top_holders", %{} = params) when has_labels(params) do
    {include_labels_str, included_labels_params} =
      include_labels_str_args(params, trailing_and: false)

    {exclude_labels_str, excluded_labels_params} =
      exclude_labels_str_args(params, trailing_and: true)

    {from, to, interval_sec, span} = timerange_parameters(params.from, params.to, params.interval)

    sql = """
    SELECT dt, SUM(value), toUInt32(SUM(has_changed))
    FROM (
      SELECT
        #{to_unix_timestamp_from_number(params.interval, from_argument_name: "from")} AS dt,
        toFloat64(0) AS value,
        toUInt32(0) AS has_changed
      FROM numbers({{span}})

      UNION ALL

      SELECT dt, SUM(value) AS value, 1 AS has_changed
      FROM (
        SELECT * FROM (
          SELECT
            #{aggregation(params.aggregation, "value", "dt")} / {{decimals}} AS value,
            #{to_unix_timestamp(params.interval, "dt", argument_name: "interval")} AS dt,
            address
          FROM #{params.table} FINAL
          WHERE
            #{exclude_labels_str}
            contract = {{contract}} AND
            dt >= toDateTime({{from}}) AND
            dt < toDateTime({{to}}) AND
            rank IS NOT NULL AND rank > 0
          GROUP BY dt, address
          ORDER BY dt, value DESC
        )
        #{include_labels_str}
        LIMIT {{limit}} BY dt
      )
      GROUP BY dt
      ORDER BY dt
    )
    GROUP BY dt
    ORDER BY dt
    """

    params =
      %{
        interval: interval_sec,
        contract: params.contract,
        limit: params.count,
        from: from,
        to: to,
        span: span,
        blockchain: params.blockchain,
        decimals: Integer.pow(10, params.decimals)
      }
      |> Map.merge(included_labels_params)
      |> Map.merge(excluded_labels_params)

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def timeseries_data_query("amount_in_top_holders", params) do
    decimals = Integer.pow(10, params.decimals)

    {from, to, interval_sec, span} = timerange_parameters(params.from, params.to, params.interval)

    sql = """
    SELECT dt, SUM(value), toUInt32(SUM(has_changed))
    FROM (
      SELECT
        #{to_unix_timestamp_from_number(params.interval, from_argument_name: "from")} AS dt,
        toFloat64(0) AS value,
        toUInt32(0) AS has_changed
      FROM numbers({{span}})

      UNION ALL

      SELECT dt, SUM(value) AS value, 1 AS has_changed
      FROM (
        SELECT * FROM (
          SELECT
            #{to_unix_timestamp(params.interval, "dt", argument_name: "interval")} AS dt,
            #{aggregation(params.aggregation, "value", "dt")} / #{decimals} AS value
          FROM #{params.table} FINAL
          WHERE
            contract = {{contract}} AND
            rank <= {{limit}} AND
            dt >= toDateTime({{from}}) AND
            dt < toDateTime({{to}}) AND
            rank IS NOT NULL AND rank > 0
          GROUP BY dt, address
          ORDER BY dt, value desc
        )
        LIMIT {{limit}} BY dt
      )
      GROUP BY dt
      ORDER BY dt
    )
    GROUP BY dt
    ORDER BY dt
    """

    params = %{
      interval: interval_sec,
      contract: params.contract,
      limit: params.count,
      from: from,
      to: to,
      span: span
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def timeseries_data_query("amount_in_exchange_top_holders", params) do
    params =
      params
      |> Map.drop([:include_labels, :exclude_labels])
      |> Map.put(:include_labels, ["centralized_exchange", "decentralized_exchange"])

    timeseries_data_query("amount_in_top_holders", params)
  end

  def timeseries_data_query("amount_in_non_exchange_top_holders", params) do
    params =
      params
      |> Map.drop([:include_labels, :exclude_labels])
      |> Map.put(:exclude_labels, ["centralized_exchange", "decentralized_exchange"])

    timeseries_data_query("amount_in_top_holders", params)
  end

  def first_datetime_query(table, contract) do
    sql = """
    SELECT
      toUnixTimestamp(toDateTime(min(dt)))
    FROM #{table}
    WHERE
      contract = {{contract}}
    """

    params = %{contract: contract}
    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def last_datetime_computed_at_query(table, contract) do
    sql = """
    SELECT
      toUnixTimestamp(max(dt))
    FROM #{table} FINAL
    WHERE
      contract = {{contract}}
    """

    params = %{contract: contract}
    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp include_labels_str_args(params, opts) do
    case Map.get(params, :include_labels) do
      [_ | _] = labels ->
        labels_str = """
        GLOBAL ANY INNER JOIN (
          SELECT address
          FROM current_label_addresses
          WHERE
              blockchain = {{blockchain}}
              AND label_id IN (
                  SELECT label_id FROM label_metadata WHERE key IN ({{included_labels}})
              )
        ) USING address
        """

        labels_str =
          if Keyword.get(opts, :trailing_and), do: labels_str <> " AND", else: labels_str

        {labels_str, %{included_labels: labels}}

      _ ->
        {"", %{}}
    end
  end

  defp exclude_labels_str_args(params, opts) do
    case Map.get(params, :exclude_labels) do
      [_ | _] = labels ->
        labels_str = """
        address GLOBAL NOT IN (
          SELECT address
          FROM current_label_addresses
          WHERE
              blockchain = {{blockchain}}
              AND label_id IN (
                  SELECT label_id FROM label_metadata WHERE key IN ({{excluded_labels}})
              )
        )
        """

        labels_str =
          if Keyword.get(opts, :trailing_and), do: labels_str <> " AND", else: labels_str

        {labels_str, %{excluded_labels: labels}}

      _ ->
        {"", %{}}
    end
  end
end
