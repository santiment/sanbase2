defmodule Sanbase.Clickhouse.Metric do
  @table "daily_metrics_v2"

  @moduledoc ~s"""
  Provide access to the v2 metrics in Clickhouse

  The metrics are stored in the '#{@table}' clickhouse table where each metric
  is defined by a `metric_id` and every project is defined by an `asset_id`.
  """

  use Ecto.Schema
  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  # The metrics that are available are described in a JSON file
  @external_resource available_metrics_file = Path.join(__DIR__, "available_v2_metrics.json")
  @metrics_json File.read!(available_metrics_file) |> Jason.decode!()
  @metrics_list @metrics_json |> Enum.map(fn %{"metric" => metric} -> metric end)
  @metrics_mapset MapSet.new(@metrics_list)

  @metric_access_map @metrics_json
                     |> Enum.map(&{&1["metric"], &1["access"] |> String.to_existing_atom()})
                     |> Map.new()

  @metric_aggregation_map @metrics_json
                          |> Enum.map(&{&1["metric"], &1["aggregation"]})
                          |> Map.new()

  def metric_access_map(), do: @metric_access_map

  @type slug :: String.t()
  @type metric :: String.t()
  @type interval :: String.t()
  @type metric_result :: %{datetime: Datetime.t(), value: float()}
  @type aggregation :: nil | :any | :sum | :avg | :min | :max | :last | :first | :median
  @aggregations [nil, :any, :sum, :avg, :min, :max, :last, :first, :median]

  schema @table do
    field(:datetime, :utc_datetime, source: :dt)
    field(:asset_id, :integer)
    field(:metric_id, :integer)
    field(:value, :float)
    field(:computed_at, :utc_datetime)
  end

  @doc ~s"""
  Get a given metric for a slug and time range. The metric's aggregation
  function can be changed by the last optional parameter. The available
  aggregations are #{inspect(@aggregations -- [nil])}
  """
  @spec get(metric, slug, DateTime.t(), DateTime.t(), interval, aggregation) ::
          {:ok, list(metric_result)} | {:error, String.t()}
  def get(slug, metric, from, to, interval, aggregation \\ nil)

  def get(_metric, _slug, _from, _to, _interval, aggregation)
      when aggregation not in @aggregations do
    {:error, "The aggregation '#{inspect(aggregation)}' is not supported"}
  end

  def get(metric, slug, from, to, interval, aggregation) do
    case metric in @metrics_mapset do
      false ->
        metric_not_available_error(metric)

      true ->
        aggregation = aggregation || Map.get(@metric_aggregation_map, metric, :last)
        get_metric(metric, slug, from, to, interval, aggregation)
    end
  end

  @spec available_metrics() :: {:ok, list(String.t())}
  def available_metrics(), do: {:ok, @metrics_list}

  @spec available_slugs() :: {:ok, list(String.t())} | {:error, String.t()}
  def available_slugs(), do: get_available_slugs()

  @spec available_aggregations() :: {:ok, list(atom())}
  def available_aggregations(), do: {:ok, @aggregations}

  # Private functions

  defp metric_not_available_error(metric) do
    close = Enum.find(@metrics_mapset, fn m -> String.jaro_distance(metric, m) > 0.9 end)
    error_msg = "The metric '#{inspect(metric)}' is not available."

    case close do
      nil -> {:error, error_msg}
      close -> {:error, error_msg <> " Did you mean '#{close}'?"}
    end
  end

  defp get_available_slugs() do
    {query, args} = available_slugs_query()

    ClickhouseRepo.query_transform(query, args, fn [slug] -> slug end)
  end

  defp get_metric(metric, slug, from, to, interval, aggregation) do
    {query, args} = metric_query(metric, slug, from, to, interval, aggregation)

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

  defp metric_query(metric, slug, from, to, interval, aggregation) do
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

  defp available_slugs_query() do
    query = """
    SELECT DISTINCT(name) FROM asset_metadata
    """

    args = []

    {query, args}
  end
end
