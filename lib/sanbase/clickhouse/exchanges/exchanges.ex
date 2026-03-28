defmodule Sanbase.Clickhouse.Exchanges do
  alias Sanbase.ClickhouseRepo, as: ClickhouseRepo
  alias Sanbase.Clickhouse.MetricAdapter.Registry

  import Sanbase.Metric.SqlQuery.Helper, only: [asset_id_filter: 2]

  def top_exchanges_by_balance(%{slug: slug}, limit, _opts \\ []) when is_binary(slug) do
    case top_exchanges_by_balance_query(slug, limit) do
      {:error, _} = error ->
        error

      %Sanbase.Clickhouse.Query{} = query_struct ->
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
                if(first_seen_dt,
                  do: DateTime.diff(DateTime.utc_now(), first_seen_dt, :day) |> abs()
                )
            }
          end
        )
    end
  end

  def owners_by_slug_and_metric(metric, slug) do
    table = Map.get(Registry.table_map(), metric)

    case not is_nil(table) && table =~ "label" do
      true ->
        query_struct = owners_by_slug_and_metric_query(metric, slug)

        ClickhouseRepo.query_transform(query_struct, fn [owner] -> owner end)

      false ->
        {:error, "The provided metric #{metric} is not a label-based metric"}
    end
  end

  def labels_by_slug_metric_and_owner(metric, slug, owner) do
    table = Map.get(Registry.table_map(), metric)

    case not is_nil(table) && table =~ "label" do
      true ->
        query_struct = labels_by_slug_metric_and_owner_query(metric, slug, owner)

        ClickhouseRepo.query_transform(query_struct, fn [label] -> label end)

      false ->
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

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp labels_by_slug_metric_and_owner_query(metric, slug, owner) do
    params = %{
      metric: Map.get(Registry.name_to_metric_map(), metric),
      slug: slug,
      owner: owner
    }

    sql = """
    SELECT DISTINCT label
    FROM #{Map.get(Registry.table_map(), metric)}
    WHERE
      metric_id = get_metric_id({{metric}})
      #{if slug, do: "AND asset_id = get_asset_id({{slug}})"}
      #{if owner, do: "AND owner = {{owner}}"}
    """

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp top_exchanges_by_balance_query(slug, limit) do
    case Sanbase.Project.slug_to_blockchain(slug) do
      {:error, _} = error -> error
      blockchain -> do_top_exchanges_by_balance_query(slug, limit, blockchain)
    end
  end

  defp do_top_exchanges_by_balance_query(slug, limit, blockchain) do
    params = %{
      slug: slug,
      limit: limit,
      blockchain: blockchain
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
        SELECT label_id, dt, value
        FROM labeled_intraday_metrics_v2
        WHERE
            label_id IN (SELECT label_id FROM exchange_label_ids)
            AND blockchain = {{blockchain}}
            AND #{asset_id_filter(%{slug: slug}, argument_name: "slug")}
            AND metric_id = dictGet(metrics_by_name, 'metric_id', 'combined_labeled_balance')
    ),
    all_balances AS (
        SELECT
            label_id,
            argMax(value, dt) AS latest_balance,
            argMinIf(value, dt, dt >= today() - INTERVAL 1 DAY) AS balance_1d,
            argMinIf(value, dt, dt >= today() - INTERVAL 7 DAY) AS balance_7d,
            argMinIf(value, dt, dt >= today() - INTERVAL 30 DAY) AS balance_30d,
            min(dt) AS first_seen
        FROM interesting_metrics
        GROUP BY label_id
    )
    SELECT DISTINCT
        dictGet(labels, 'value', all_balances.label_id) AS owner,
        exchange_label_ids.cex_or_dex_label,
        all_balances.latest_balance,
        all_balances.balance_1d - all_balances.latest_balance AS balance_change_1d,
        all_balances.balance_7d - all_balances.latest_balance AS balance_change_7d,
        all_balances.balance_30d - all_balances.latest_balance AS balance_change_30d,
        toUnixTimestamp(all_balances.first_seen) AS first_seen_ts
    FROM all_balances
    LEFT JOIN exchange_label_ids ON (exchange_label_ids.label_id = all_balances.label_id)
    ORDER BY latest_balance DESC
    LIMIT {{limit}}
    """

    Sanbase.Clickhouse.Query.new(sql, params)
  end
end
