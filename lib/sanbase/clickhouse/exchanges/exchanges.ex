defmodule Sanbase.Clickhouse.Exchanges do
  @moduledoc false
  import Sanbase.Metric.SqlQuery.Helper, only: [asset_id_filter: 2]

  alias Sanbase.Clickhouse.MetricAdapter.Registry
  alias Sanbase.Clickhouse.Query

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  def top_exchanges_by_balance(%{slug: slug}, limit, _opts \\ []) when is_binary(slug) do
    query_struct = top_exchanges_by_balance_query(slug, limit)

    ClickhouseRepo.query_transform(
      query_struct,
      fn [owner, label, balance, change_1d, change_7d, change_30d, first_seen_ts] ->
        first_seen_dt = if first_seen_ts, do: DateTime.from_unix!(first_seen_ts)

        %{
          owner: owner,
          label: label,
          balance: balance,
          balance_change1d: change_1d,
          balance_change7d: change_7d,
          balance_change30d: change_30d,
          datetime_of_first_transfer: first_seen_dt,
          days_since_first_transfer:
            if(first_seen_dt, do: DateTime.utc_now() |> DateTime.diff(first_seen_dt, :day) |> abs())
        }
      end
    )
  end

  def owners_by_slug_and_metric(metric, slug) do
    table = Map.get(Registry.table_map(), metric)

    if not is_nil(table) && table =~ "label" do
      query_struct = owners_by_slug_and_metric_query(metric, slug)

      ClickhouseRepo.query_transform(query_struct, fn [owner] -> owner end)
    else
      {:error, "The provided metric #{metric} is not a label-based metric"}
    end
  end

  # Private functions

  defp owners_by_slug_and_metric_query(metric, slug) do
    params = %{
      metric: Map.get(Registry.name_to_metric_map(), metric),
      slug: slug
    }

    sql = """
    SELECT DISTINCT owner
    FROM #{Map.get(Registry.table_map(), metric)}
    WHERE
      metric_id = get_metric_id({{metric}})
      #{if slug, do: "AND asset_id = get_asset_id({{slug}})"}
    """

    Query.new(sql, params)
  end

  defp top_exchanges_by_balance_query(slug, limit) do
    params = %{
      slug: slug,
      limit: limit,
      blockchain: Sanbase.Project.slug_to_blockchain(slug)
    }

    sql = """
    WITH address_hashes AS (
        SELECT
            cityHash64(address) AS address_hash, address,
            if(
                dictGet('labels', 'key', label_id) = 'centralized_exchange',
                'centralized_exchange',
                'decentralized_exchange'
            ) AS cex_or_dex_label
        FROM current_label_addresses
        WHERE blockchain = {{blockchain}}
            AND label_id IN (
                dictGet('default.labels_by_fqn', 'label_id', tuple('santiment/centralized_exchange:v1')),
                dictGet('default.labels_by_fqn', 'label_id', tuple('santiment/decentralized_exchange:v1'))
            )
    ),
    exchange_label_ids AS (
        SELECT label_id, cex_or_dex_label
        FROM current_label_addresses cla
        LEFT JOIN address_hashes ah USING address
        WHERE
            blockchain = {{blockchain}}
            AND label_id IN (SELECT label_id FROM label_metadata WHERE key = 'owner')
            AND cityHash64(address) IN (SELECT address_hash FROM address_hashes)
            AND dictGet('labels', 'value', label_id) != ''
    ),
    interesting_metrics AS (
        SELECT *
        FROM labeled_intraday_metrics_v2
        WHERE
            label_id IN (SELECT label_id FROM exchange_label_ids)
            AND blockchain = {{blockchain}}
            AND #{asset_id_filter(%{slug: slug}, argument_name: "slug")}
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
    SELECT DISTINCT
        dictGet(labels, 'value', latest_balance.label_id) AS owner,
        exchange_label_ids.cex_or_dex_label,
        latest_balance.latest_balance,
        balance_1d.balance_1d - latest_balance AS balance_change_1d,
        balance_7d.balance_7d - latest_balance AS balance_change_7d,
        balance_30d.balance_30d - latest_balance AS balance_change_30d,
        toUnixTimestamp(first_seen.first_seen) AS first_seen_ts
    FROM latest_balance
    LEFT JOIN balance_1d ON (balance_1d.label_id = latest_balance.label_id)
    LEFT JOIN balance_7d ON (balance_7d.label_id = latest_balance.label_id)
    LEFT JOIN balance_30d ON (balance_30d.label_id = latest_balance.label_id)
    LEFT JOIN first_seen ON (first_seen.label_id = latest_balance.label_id)
    LEFT JOIN exchange_label_ids ON (exchange_label_ids.label_id = latest_balance.label_id)
    ORDER BY latest_balance DESC
    LIMIT {{limit}}
    """

    Query.new(sql, params)
  end
end
