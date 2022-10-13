defmodule Sanbase.Clickhouse.TopHolders.SqlQuery do
  @moduledoc false

  import Sanbase.DateTimeUtils
  import Sanbase.Metric.SqlQuery.Helper, only: [aggregation: 3]

  defguard has_labels(map)
           when (is_map_key(map, :include_labels) and
                   is_list(:erlang.map_get(:include_labels, map)) and
                   length(:erlang.map_get(:include_labels, map)) > 0) or
                  (is_map_key(map, :exclude_labels) and
                     is_list(:erlang.map_get(:exclude_labels, map)) and
                     length(:erlang.map_get(:exclude_labels, map)) > 0)

  def timeseries_data_query("amount_in_top_holders", %{} = params) when has_labels(params) do
    decimals = Sanbase.Math.ipow(10, params.decimals)

    args = [
      params.interval |> str_to_sec(),
      params.contract,
      params.count,
      params.from |> DateTime.to_unix(),
      params.to |> DateTime.to_unix(),
      params.blockchain
    ]

    # This will return the proper IN/NOT IN labels string and will update
    # the args with by appending the arguments to the end. The include/exclude
    # strings are using different strategies - a where clause and an inner join.
    # The reason for this is perfromance - in some cases the query would need
    # more than the allowed RAM usage and would fail otherwise.
    {include_labels_str, args} =
      include_labels_str_args(params, args, trailing_and: false, blockchain_arg_position: 6)

    {exclude_labels_str, args} =
      exclude_labels_str_args(params, args, trailing_and: true, blockchain_arg_position: 6)

    query = """
    SELECT dt, SUM(value) AS value
    FROM (
      SELECT
        #{aggregation(params.aggregation, "value", "dt")} / #{decimals} AS value,
        toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?1) * ?1) AS dt,
        address
      FROM #{params.table} FINAL
      #{table_to_where_keyword(params.table)}
        #{exclude_labels_str}
        contract = ?2 AND
        dt >= toDateTime(?4) AND
        dt < toDateTime(?5) AND
        rank IS NOT NULL AND rank > 0
      GROUP BY dt, address
      ORDER BY dt, value DESC
    )
    #{include_labels_str}
    GROUP BY dt
    ORDER BY dt
    LIMIT ?3 BY dt
    """

    {query, args}
  end

  def timeseries_data_query("amount_in_top_holders", params) do
    decimals = Sanbase.Math.ipow(10, params.decimals)

    query = """
    SELECT dt, SUM(value)
    FROM (
      SELECT
        toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?1) * ?1) AS dt,
        #{aggregation(params.aggregation, "value", "dt")} / #{decimals} AS value
      FROM #{params.table} FINAL
      #{table_to_where_keyword(params.table)}
        contract = ?2 AND
        rank <= ?3 AND
        dt >= toDateTime(?4) AND
        dt < toDateTime(?5) AND
        rank IS NOT NULL AND rank > 0
      GROUP BY dt, address
      ORDER BY dt, value desc
      LIMIT ?3 BY dt
    )
    GROUP BY dt
    ORDER BY dt
    """

    args = [
      params.interval |> str_to_sec(),
      params.contract,
      params.count,
      params.from |> DateTime.to_unix(),
      params.to |> DateTime.to_unix()
    ]

    {query, args}
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
    query = """
    SELECT
      toUnixTimestamp(toDateTime(min(dt)))
    FROM #{table}
    #{table_to_where_keyword(table)}
      contract = ?1
    """

    args = [contract]
    {query, args}
  end

  def last_datetime_computed_at_query(table, contract) do
    query = """
    SELECT
      toUnixTimestamp(max(dt))
    FROM #{table} FINAL
    #{table_to_where_keyword(table)}
      contract = ?1
    """

    args = [contract]

    {query, args}
  end

  defp table_to_where_keyword(table) do
    case String.contains?(table, "union") do
      true -> "WHERE"
      false -> "PREWHERE"
    end
  end

  defp include_labels_str_args(params, args, opts) do
    args_length = length(args)

    case Map.get(params, :include_labels) do
      [_ | _] = labels ->
        blockchain_arg_position = Keyword.fetch!(opts, :blockchain_arg_position)

        labels_str = """
        GLOBAL ANY INNER JOIN (
          SELECT address
          FROM(
            SELECT address, argMax(sign, version) AS sign
            FROM blockchain_address_labels
            PREWHERE blockchain = ?#{blockchain_arg_position} AND label IN (?#{args_length + 1})
            GROUP BY blockchain, asset_id, label, address
            HAVING sign = 1
          )
        ) USING address
        """

        {labels_str, args ++ [labels]}

      _ ->
        {"", args}
    end
  end

  defp exclude_labels_str_args(params, args, opts) do
    args_length = length(args)

    case Map.get(params, :exclude_labels) do
      [_ | _] = labels ->
        blockchain_arg_position = Keyword.fetch!(opts, :blockchain_arg_position)

        labels_str = """
        address GLOBAL NOT IN (
          SELECT address
          FROM(
            SELECT address, argMax(sign, version) AS sign
            FROM blockchain_address_labels
            PREWHERE blockchain = ?#{blockchain_arg_position} AND label IN(?#{args_length + 1})
            GROUP BY blockchain, asset_id, label, address
            HAVING sign = 1
          )
        )
        """

        labels_str =
          if Keyword.get(opts, :trailing_and), do: labels_str <> " AND", else: labels_str

        {labels_str, args ++ [labels]}

      _ ->
        {"", args}
    end
  end
end
