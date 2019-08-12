defmodule Sanbase.Clickhouse.Metric do
  @table "daily_metrics_v2"

  @moduledoc ~s"""
  Provide access to the v2 metrics in Clickhouse

  The metrics are stored in the '#{@table}' clickhouse table where each metric
  is defined by a `metric_id` and every project is defined by an `asset_id`.
  """

  use Ecto.Schema
  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @metrics_file "available_v2_metrics.json"
  @external_resource available_metrics_file = Path.join(__DIR__, @metrics_file)
  @metrics_json File.read!(available_metrics_file) |> Jason.decode!()
  @metrics_list @metrics_json |> Enum.map(fn %{"metric" => metric} -> metric end)
  @metrics_mapset MapSet.new(@metrics_list)
  @aggregations [nil, :any, :sum, :avg, :min, :max, :last, :first, :median]

  @metric_access_map @metrics_json
                     |> Enum.map(&{&1["metric"], &1["access"] |> String.to_existing_atom()})
                     |> Map.new()

  @free_metrics @metric_access_map
                |> Enum.filter(fn {_m, a} -> a == :free end)
                |> Keyword.keys()

  @restricted_metrics @metric_access_map
                      |> Enum.filter(fn {_m, a} -> a == :restricted end)
                      |> Keyword.keys()

  @metric_aggregation_map @metrics_json
                          |> Enum.map(&{&1["metric"], &1["aggregation"] |> String.to_atom()})
                          |> Map.new()

  case Enum.filter(@metric_aggregation_map, fn {_, aggr} -> aggr not in @aggregations end) do
    [] ->
      :ok

    metrics ->
      require(Sanbase.Break, as: Break)

      Break.break("""
      There are metrics defined in the #{@metrics_file} that have not supported aggregation.
      These metrics are: #{inspect(metrics |> Enum.map(fn {m, _} -> m end))}
      """)
  end

  def free_metrics(), do: @free_metrics
  def restricted_metrics(), do: @restricted_metrics
  def metric_access_map(), do: @metric_access_map

  @type slug :: String.t()
  @type metric :: String.t()
  @type interval :: String.t()
  @type metric_result :: %{datetime: Datetime.t(), value: float()}
  @type aggregation :: nil | :any | :sum | :avg | :min | :max | :last | :first | :median

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
  def get(metric, slug, from, to, interval, aggregation \\ nil)

  def get(_metric, _slug, _from, _to, _interval, aggregation)
      when aggregation not in @aggregations do
    {:error, "The aggregation '#{inspect(aggregation)}' is not supported"}
  end

  def get(metric, slug, from, to, interval, aggregation) do
    case metric in @metrics_mapset do
      false ->
        metric_not_available_error(metric)

      true ->
        aggregation = aggregation || Map.get(@metric_aggregation_map, metric)
        get_metric(metric, slug, from, to, interval, aggregation)
    end
  end

  def metadata(metric) do
    case metric in @metrics_mapset do
      false ->
        metric_not_available_error(metric)

      true ->
        get_metadata(metric)
    end
  end

  @spec available_metrics() :: {:ok, list(String.t())}
  def available_metrics(), do: {:ok, @metrics_list}

  @spec available_slugs() :: {:ok, list(String.t())} | {:error, String.t()}
  def available_slugs(), do: get_available_slugs()

  @spec available_aggregations() :: {:ok, list(atom())}
  def available_aggregations(), do: {:ok, @aggregations}

  def first_datetime(slug) when is_binary(slug) do
    {query, args} = first_datetime_query(slug)

    ClickhouseRepo.query_transform(query, args, fn [datetime] ->
      DateTime.from_unix!(datetime)
    end)
    |> case do
      {:ok, [result]} -> {:ok, result}
      {:error, error} -> {:error, error}
    end
  end

  # Private functions

  defp metric_not_available_error(metric) do
    close = Enum.find(@metrics_mapset, fn m -> String.jaro_distance(metric, m) > 0.9 end)
    error_msg = "The metric '#{inspect(metric)}' is not available."

    case close do
      nil -> {:error, error_msg}
      close -> {:error, error_msg <> " Did you mean '#{close}'?"}
    end
  end

  defp get_metadata(metric) do
    min_interval = min_interval(metric)
    default_aggregation = Map.get(@metric_aggregation_map, metric)

    {:ok,
     %{
       min_interval: min_interval,
       default_aggregation: default_aggregation
     }}
  end

  defp min_interval(metric), do: "1d"

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
        argMax(value, computed_at) AS value
      FROM #{@table}
      PREWHERE
          dt >= toDateTime(?3) AND
          dt < toDateTime(?4) AND
          asset_id = (
            SELECT argMax(asset_id, computed_at)
            FROM asset_metadata
            PREWHERE name = ?5
          ) AND
          metric_id = (
            SELECT
              argMax(metric_id, computed_at) AS metric_id
            FROM
              metric_metadata
            PREWHERE
              name = ?2
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

  defp first_datetime_query(slug) do
    query = """
    SELECT
      toUnixTimestamp(toDateTime(min(dt)))
    FROM #{@table}
    PREWHERE
      asset_id = (
        SELECT argMax(asset_id, computed_at)
        FROM asset_metadata
        PREWHERE name = ?1
      ) AND
      value > 0
    """

    args = [slug]

    {query, args}
  end
end
