defmodule Sanbase.Clickhouse.Metric.TableSqlQuery do
  alias Sanbase.Clickhouse.Metric.FileHandler

  @table_map FileHandler.table_map()
  @name_to_metric_map FileHandler.name_to_metric_map()

  def table_data_query("labelled_exchange_balance_sum" = metric, slug_or_slugs, from, to) do
    slugs = List.wrap(slug_or_slugs)

    # Build as string part of the query so that it can be interpolated in the full query.
    # It is built with positional parameters so the user input can be passed as
    # parameters and not directly interpolated in the string. This allows for an
    # arbitrary number of slugs and to control their order.
    sum_if_argument =
      slugs
      |> Enum.with_index(5)
      |> Enum.map(fn {_slug, index} ->
        ~s/sumIf(value, name=?#{index}) AS slugNum#{index}/
      end)
      |> Enum.join(",\n")

    query = """
    SELECT
      label,
      owner,
      #{sum_if_argument}
    FROM (
      SELECT label, owner, name, value
      FROM (
        SELECT dt, label, owner, asset_id, value
        FROM #{Map.get(@table_map, metric)} FINAL
        PREWHERE
          dt >= toDateTime(?2) AND
          dt < toDateTime(?3) AND
          asset_id IN (SELECT asset_id FROM asset_metadata FINAL PREWHERE name IN (?4)) AND
          metric_id = (SELECT metric_id FROM metric_metadata PREWHERE (name = ?1))
      )
      GLOBAL ANY LEFT JOIN (
        SELECT asset_id, argMax(name, computed_at) AS name FROM asset_metadata FINAL GROUP BY asset_id
      ) USING asset_id
    )
    GROUP BY label, owner
    """

    # `++ slugs` will add `length(slugs)` number of arguments and not a single
    # list to the end. This is done so the every sumIf in `sum_if_argument` could
    # properly add the proper index for every slug and not interpolate user-inputs
    args =
      [
        Map.get(@name_to_metric_map, metric),
        from |> DateTime.to_unix(),
        to |> DateTime.to_unix(),
        slugs
      ] ++ slugs

    {query, args}
  end
end
