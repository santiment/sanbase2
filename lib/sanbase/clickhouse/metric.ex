defmodule Sanbase.Clickhouse.Metric do
  use Ecto.Schema
  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @external_resource availalbe_metrics_file =
                       Path.join(
                         __DIR__,
                         "available_v2_metrics.json"
                       )
  @metrics_json File.read!(availalbe_metrics_file) |> Jason.decode!()

  @metrics_mapset MapSet.new(@metrics_json |> Enum.map(fn %{"metric" => metric} -> metric end))
  @metric_aggregation_map Map.new(
                            @metrics_json
                            |> Enum.map(&{&1["metric"], &1["aggregation"]})
                          )
  @aggregations [nil, :any, :sum, :avg, :min, :max, :last, :first, :median]

  @table "daily_metrics_v2"
  schema @table do
    field(:datetime, :utc_datetime, source: :dt)
    field(:asset_id, :integer)
    field(:metric_id, :integer)
    field(:value, :float)
    field(:computed_at, :utc_datetime)
  end

  def get(slug, metric, from, to, interval, aggregation \\ nil)

  def get(slug, metric, from, to, interval, aggregation)
      when aggregation in @aggregations do
    case metric in @metrics_mapset do
      false ->
        close = Enum.find(@metrics_mapset, fn m -> String.jaro_distance(metric, m) > 0.9 end)

        case close do
          nil ->
            {:error, "The metric '#{metric}' is not available"}

          close ->
            {:error, "The metric '#{metric}' is not available. Did you mean '#{close}'?"}
        end

      true ->
        do_get(
          slug,
          metric,
          from,
          to,
          interval,
          aggregation || Map.get(@metric_aggregation_map, metric, :any)
        )
    end
  end

  defp do_get(slug, metric, from, to, interval, aggregation) do
    {query, args} = metric_query(slug, metric, from, to, interval, aggregation)

    ClickhouseRepo.query_transform(query, args, fn [datetime, value] ->
      %{
        datetime: DateTime.from_unix!(datetime),
        value: value
      }
    end)
  end

  defp aggregation(:last, value_column, dt_column), do: "argMax(#{value_column}, #{dt_column})"
  defp aggregation(:first, value_column, dt_column), do: "argMin(#{value_column}, #{dt_column})"
  defp aggregation(aggr, value_column, _dt_column), do: "#{aggr}(#{value_column})"

  defp metric_query(slug, metric, from, to, interval, aggregation) do
    query = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?1) * ?1) AS t,
      #{aggregation(aggregation, "value", "t")}
    FROM(
      SELECT
        dt,
        argMaxIf(value, computed_at, metric_name = ?2) AS value
      FROM #{@table}
      INNER JOIN (
        SELECT
          name AS metric_name,
          metric_id
        FROM
          metric_metadata
        PREWHERE
          name = ?2
      ) USING metric_id
      PREWHERE
          dt >= toDateTime(?3) AND
          dt <= toDateTime(?4) AND
          asset_id = (
            SELECT argMax(asset_id, computed_at)
            FROM asset_metadata
            PREWHERE name = ?5
          )
      GROUP BY dt
    )
    GROUP BY t
    ORDER BY t
    """

    args = [
      Sanbase.DateTimeUtils.str_to_sec(interval),
      metric,
      from,
      to,
      slug
    ]

    {query, args}
  end
end
