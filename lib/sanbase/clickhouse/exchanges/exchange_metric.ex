defmodule Sanbase.Clickhouse.Exchanges.ExchangeMetric do
  import Sanbase.Metric.SqlQuery.Helper, only: [asset_id_filter: 2]

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  def top_exchanges_by_balance(%{slug: slug_or_slugs}, limit, opts \\ []) do
    filters = Keyword.get(opts, :additional_filters, [])

    additional_filters = additional_filters(filters, trailing_and: false)

    query = """
    SELECT
      owner,
      label,
      SUM( balance ) AS balance,
      SUM( change_1d ) AS change_1d,
      SUM( change_7d ) AS balance_7d,
      SUM( change_30d ) AS balance_30d,
      min( unix_ts_of_first_transfer ) AS unix_ts_of_first_transfer,
      max( days_since_first_transfer ) AS days_since_first_transfer
    FROM (
      SELECT
        owner,
        label2 AS label,
        argMaxIf( value2, dt, metric_name = 'labelled_exchange_balance_sum' ) AS balance,
        sumIf( value2, metric_name = 'labelled_exchange_balance' and dt > now() - INTERVAL 1 DAY ) AS change_1d,
        sumIf( value2, metric_name = 'labelled_exchange_balance' and dt > now() - INTERVAL 7 DAY ) AS change_7d,
        sumIf( value2, metric_name = 'labelled_exchange_balance' and dt > now() - INTERVAL 30 DAY) AS change_30d,
        toUnixTimestamp(if(
          minIf( dt, metric_name = 'labelled_exchange_balance' and abs(value2) > 0 ) = 0,
          NULL,
          minIf( dt, metric_name = 'labelled_exchange_balance' and abs(value2) > 0 )
        )) AS unix_ts_of_first_transfer,
        if(
            unix_ts_of_first_transfer > 0,
            intDivOrZero( now() - toDateTime(unix_ts_of_first_transfer), 86400 ),
            NULL
      ) AS days_since_first_transfer
      FROM (
        SELECT
          asset_id,
          if(
            label='deposit',
            'centralized_exchange',
            label
          ) AS label2,
          owner,
          dt,
          metric_name,
          argMax( value, computed_at ) AS value2

        FROM intraday_label_based_metrics FINAL

        ANY LEFT JOIN (
          SELECT name AS metric_name, metric_id FROM metric_metadata FINAL
          ) USING metric_id
        PREWHERE
          #{asset_id_filter(slug_or_slugs, argument_position: 1)} AND
          (
            (
              metric_id IN (
                SELECT metric_id
                FROM metric_metadata FINAL
                PREWHERE name IN ('labelled_exchange_balance_sum')
              ) AND
              dt >= now() - INTERVAL 7 DAY
            )
            OR
            (
              metric_id IN (
                SELECT metric_id
                FROM metric_metadata FINAL
                PREWHERE name IN ('labelled_exchange_balance')
              )
            )
          ) AND
          dt < now() AND
          dt != toDateTime('1970-01-01 00:00:00')
        GROUP BY asset_id, label2, owner, dt, metric_name
      )
      #{if(additional_filters != [], do: "WHERE #{additional_filters}")}
      GROUP BY asset_id, label, owner
    )
    GROUP BY label, owner
    ORDER BY balance DESC
    LIMIT ?2
    """

    args = [slug_or_slugs, limit]

    ClickhouseRepo.query_transform(
      query,
      args,
      fn [owner, label, balance, change_1d, change_7d, change_30d, dt, days] ->
        %{
          owner: owner,
          label: label,
          balance: balance,
          balance_change1d: change_1d,
          balance_change7d: change_7d,
          balance_change30d: change_30d,
          datetime_of_first_transfer: dt |> DateTime.from_unix!(),
          days_since_first_transfer: days
        }
      end
    )
  end

  # Add additional `=` filters to the query. This is mostly used with labeled
  # metrics where additional column filters must be applied.
  defp additional_filters([], _opts), do: []

  defp additional_filters(filters, opts) do
    filters_string =
      filters
      |> Enum.map(fn
        {column, value} when is_binary(value) ->
          "lower(#{column}) = '#{value |> String.downcase()}'"

        {column, value} when is_number(value) ->
          "#{column} = #{value}"

        {column, [value | _] = list} when is_binary(value) ->
          list = Enum.map(list, fn x -> ~s/'#{x |> String.downcase()}'/ end)
          list_str = list |> Enum.join(", ")
          "#{column} IN (#{list_str})"

        {column, [value | _] = list} when is_number(value) ->
          list_str = list |> Enum.join(", ")
          "#{column} IN (#{list_str})"
      end)
      |> Enum.join(" AND\n")

    case Keyword.get(opts, :trailing_and, false) do
      false -> filters_string
      true -> filters_string <> " AND"
    end
  end
end
