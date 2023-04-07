defmodule Sanbase.Clickhouse.Exchanges.ExchangeMetric do
  import Sanbase.Metric.SqlQuery.Helper, only: [asset_id_filter: 2, additional_filters: 3]

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  def top_exchanges_by_balance(%{slug: slug_or_slugs}, limit, opts \\ []) do
    filters = Keyword.get(opts, :additional_filters, [])
    query_struct = top_exchanges_by_balance_query(slug_or_slugs, limit, filters)

    ClickhouseRepo.query_transform(
      query_struct,
      fn [owner, label, balance, change_1d, change_7d, change_30d, ts, days] ->
        %{
          owner: owner,
          label: label,
          balance: balance,
          balance_change1d: change_1d,
          balance_change7d: change_7d,
          balance_change30d: change_30d,
          datetime_of_first_transfer: if(ts, do: ts |> DateTime.from_unix!()),
          days_since_first_transfer: days
        }
      end
    )
  end

  # Private functions

  defp top_exchanges_by_balance_query(slug_or_slugs, limit, filters) do
    params = %{slug: slug_or_slugs, limit: limit}

    {additional_filters_str, params} = additional_filters(filters, params, trailing_and: false)

    sql = """
    SELECT
      owner,
      label2 as label,
      SUM( balance ) AS balance,
      SUM( change_1d ) AS change_1d,
      SUM( change_7d ) AS balance_7d,
      SUM( change_30d ) AS balance_30d,
      min( unix_ts_of_first_transfer ) AS unix_ts_of_first_transfer,
      max( days_since_first_transfer ) AS days_since_first_transfer
    FROM (
      SELECT
        owner,
        if(
            label='deposit',
            'centralized_exchange',
            label
          ) AS label2,
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
          label,
          owner,
          dt,
          metric_name,
          argMax( value, computed_at ) AS value2

        FROM intraday_label_based_metrics

        ANY LEFT JOIN ( SELECT name AS metric_name, metric_id FROM metric_metadata FINAL ) USING metric_id
        PREWHERE
          #{asset_id_filter(%{slug: slug_or_slugs}, argument_name: "slug")} AND
          label IN ('deposit', 'centralized_exchange', 'decentralized_exchange') AND
          dt < now() AND
          dt != toDateTime('1970-01-01 00:00:00') AND
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
          )
        GROUP BY asset_id, metric_id, label, owner, dt, metric_name
      )
      #{if(additional_filters_str != "", do: "WHERE #{additional_filters_str}")}
      GROUP BY asset_id, label, owner
    )
    GROUP BY label, owner
    ORDER BY balance DESC
    LIMIT {{limit}}
    """

    Sanbase.Clickhouse.Query.new(sql, params)
  end
end
