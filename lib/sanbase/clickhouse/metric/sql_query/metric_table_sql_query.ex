defmodule Sanbase.Clickhouse.MetricAdapter.TableSqlQuery do
  @moduledoc false
  alias Sanbase.Clickhouse.MetricAdapter.Registry

  def table_data_query("labelled_exchange_balance_sum" = metric, slug_or_slugs, from, to) do
    slugs = List.wrap(slug_or_slugs)

    {sum_query_str, sum_query_params} = generate_query_and_params(slugs)

    sql = """
    SELECT
      label,
      owner,
      #{sum_query_str}
    FROM (
      SELECT label, owner, name, value
      FROM (
        SELECT dt, label, owner, asset_id, value
        FROM #{Map.get(Registry.table_map(), metric)} FINAL
        PREWHERE
          dt >= toDateTime({{from}}) AND
          dt < toDateTime({{to}}) AND
          asset_id IN (SELECT asset_id FROM asset_metadata FINAL PREWHERE name IN ({{slugs}})) AND
          metric_id = (SELECT metric_id FROM metric_metadata PREWHERE (name = {{metric}}))
      )
      GLOBAL ANY LEFT JOIN (
        SELECT asset_id, argMax(name, computed_at) AS name FROM asset_metadata FINAL GROUP BY asset_id
      ) USING asset_id
    )
    GROUP BY label, owner
    """

    params =
      Map.merge(
        %{
          metric: Map.get(Registry.name_to_metric_map(), metric),
          from: DateTime.to_unix(from),
          to: DateTime.to_unix(to),
          slugs: slugs
        },
        sum_query_params
      )

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp generate_query_and_params(slugs) do
    # Build as string part of the query so that it can be interpolated in the full query.
    # It is built with positional parameters so the user input can be passed as
    # parameters and not directly interpolated in the string. This allows for an
    # arbitrary number of slugs and to control their order.
    {slug_params, query_str} =
      slugs
      |> Enum.with_index()
      |> Enum.reduce({%{}, []}, fn {slug, index}, {map, queries} ->
        {
          Map.put(map, "slug_#{index}", slug),
          [~s/sumIf(value, name={{slug_#{index}}}) / | queries]
        }
      end)

    query_str = query_str |> Enum.reverse() |> Enum.join(", ")
    {query_str, slug_params}
  end
end
