defmodule Sanbase.Clickhouse.Exchanges do
  alias Sanbase.Clickhouse.MetricAdapter.FileHandler

  import Sanbase.Metric.SqlQuery.Helper, only: [asset_id_filter: 2, additional_filters: 3]

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @name_to_metric_map FileHandler.name_to_metric_map()
  @table_map FileHandler.table_map()

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

  def owners_by_slug_and_metric(metric, slug) do
    table = Map.get(@table_map, metric)

    case not is_nil(table) && table =~ "label" do
      true ->
        query_struct = owners_by_slug_and_metric_query(metric, slug)

        ClickhouseRepo.query_transform(query_struct, fn [owner] -> owner end)

      false ->
        {:error, "The provided metric #{metric} is not a label-based metric"}
    end
  end

  # Private functions

  defp owners_by_slug_and_metric_query(metric, slug) do
    params = %{
      metric: Map.get(@name_to_metric_map, metric),
      slug: slug
    }

    sql = """
    SELECT DISTINCT owner
    FROM #{Map.get(@table_map, metric)}
    WHERE
      metric_id = get_metric_id({{metric}})
      #{if slug, do: "AND asset_id = get_asset_id({{slug}})"}
    """

    Sanbase.Clickhouse.Query.new(sql, params)
  end

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

    sql = """
    WITH
    address_hashes AS (
        SELECT cityHash64(address)
        FROM current_label_addresses
        WHERE
            blockchain = 'ethereum'
            AND label_id IN (
                dictGet('default.labels_by_fqn', 'label_id', tuple('santiment/centralized_exchange:v1')),
                dictGet('default.labels_by_fqn', 'label_id', tuple('santiment/decentralized_exchange:v1'))
            )
    ),
    exchange_label_ids AS (
        SELECT label_id
        FROM current_label_addresses
        WHERE
            blockchain = 'ethereum'
            AND label_id IN (SELECT label_id FROM label_metadata WHERE key = 'owner')
            AND cityHash64(address) IN address_hashes
            AND dictGet('labels', 'value', label_id) != ''
    ),
    interesting_metrics AS (
        SELECT *
        FROM labeled_intraday_metrics
        WHERE
            label_id IN (exchange_label_ids)
            AND blockchain = 'ethereum'
            AND #{asset_id_filter(%{slug: slug_or_slugs}, argument_name: "slug")}
            AND metric_id = dictGet(metrics_by_name, 'metric_id', 'combined_labeled_balance')
    ),
    latest_balance AS (
        SELECT label_id, argMax(value, dt) AS latest_balance
        FROM interesting_metrics
        WHERE dt >= today() - INTERVAL 7 DAY
        GROUP BY label_id
    ),
    balance_1d AS (
        SELECT label_id, argMin(value, dt) AS balance_1d
        FROM interesting_metrics
        WHERE dt >= today() - INTERVAL 1 DAY
        GROUP BY label_id
    ),
    balance_7d AS (
        SELECT label_id, argMin(value, dt) AS balance_7d
        FROM interesting_metrics
        WHERE dt >= today() - INTERVAL 7 DAY
        GROUP BY label_id
    ),
    balance_30d AS (
        SELECT label_id, argMin(value, dt) AS balance_30d
        FROM interesting_metrics
        WHERE dt >= today() - INTERVAL 30 DAY
        GROUP BY label_id
    ),
    first_seen AS (
        SELECT label_id, min(dt) AS first_seen
        FROM interesting_metrics
        GROUP BY label_id
    )

    SELECT
        dictGet(labels, 'value', latest_balance.label_id) AS label,
        latest_balance.latest_balance,
        balance_1d.balance_1d - latest_balance AS balance_change_1d,
        balance_7d.balance_7d - latest_balance AS balance_change_7d,
        balance_30d.balance_30d - latest_balance AS balance_change_30d,
        first_seen.first_seen
    FROM latest_balance
    LEFT JOIN balance_1d ON (balance_1d.label_id = latest_balance.label_id)
    LEFT JOIN balance_7d ON (balance_7d.label_id = latest_balance.label_id)
    LEFT JOIN balance_30d ON (balance_30d.label_id = latest_balance.label_id)
    LEFT JOIN first_seen ON (first_seen.label_id = latest_balance.label_id)
    ORDER BY latest_balance DESC
    LIMIT 10;
    """

    Sanbase.Clickhouse.Query.new(sql, params)
  end
end
