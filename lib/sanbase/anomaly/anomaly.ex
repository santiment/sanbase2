defmodule Sanbase.Anomaly do
  import Sanbase.Anomaly.SqlQuery
  import Sanbase.Clickhouse.MetadataHelper

  alias Sanbase.Anomaly.FileHandler

  alias Sanbase.ClickhouseRepo

  @aggregations FileHandler.aggregations()
  @aggregation_map FileHandler.aggregation_map()
  @anomalies_mapset FileHandler.anomalies_mapset()
  @min_interval_map FileHandler.min_interval_map()
  @anomalies @anomalies_mapset |> Enum.to_list()
  @metric_map FileHandler.metric_map()
  @data_type_map FileHandler.data_type_map()
  @metric_and_model_to_anomaly_map FileHandler.metric_and_model_to_anomaly_map()

  def has_anomaly?(anomaly) do
    case anomaly in @anomalies_mapset do
      true -> true
      false -> anomaly_not_available_error(anomaly)
    end
  end

  def available_anomalies(), do: @anomalies

  def available_anomalies(slug) do
    Sanbase.Cache.get_or_store(
      {__MODULE__, :slug_to_anomalies_map} |> Sanbase.Cache.hash(),
      fn -> slug_to_anomalies_map() end
    )
    |> case do
      {:ok, map} -> {:ok, Map.get(map, slug, [])}
      {:error, error} -> {:error, error}
    end
  end

  def available_slugs(anomaly) do
    {query, args} = available_slugs_query(anomaly)

    ClickhouseRepo.query_transform(query, args, fn [slug] -> slug end)
  end

  def metadata(anomaly) do
    default_aggregation = Map.get(@aggregation_map, anomaly)

    {:ok,
     %{
       anomaly: anomaly,
       metric: Map.get(@metric_map, anomaly),
       min_interval: Map.get(@min_interval_map, anomaly),
       default_aggregation: default_aggregation,
       available_aggregations: @aggregations,
       data_type: Map.get(@data_type_map, anomaly)
     }}
  end

  def first_datetime(anomaly, slug \\ nil)

  def first_datetime(anomaly, slug) do
    {query, args} = first_datetime_query(anomaly, slug)

    ClickhouseRepo.query_transform(query, args, fn [datetime] ->
      DateTime.from_unix!(datetime)
    end)
    |> case do
      {:ok, [result]} -> {:ok, result}
      {:error, error} -> {:error, error}
    end
  end

  def timeseries_data(anomaly, slug, from, to, interval, aggregation \\ nil)

  def timeseries_data(anomaly, slug, from, to, interval, aggregation) do
    aggregation = aggregation || Map.get(@aggregation_map, anomaly)
    {query, args} = timeseries_data_query(anomaly, slug, from, to, interval, aggregation)

    ClickhouseRepo.query_transform(query, args, fn [unix, value] ->
      %{
        datetime: DateTime.from_unix!(unix),
        value: value
      }
    end)
  end

  def aggregated_timeseries_data(anomaly, slug_or_slugs, from, to, aggregation \\ nil)
  def aggregated_timeseries_data(_anomaly, [], _from, _to, _aggregation), do: {:ok, []}

  def aggregated_timeseries_data(anomaly, slug_or_slugs, from, to, aggregation)
      when is_binary(slug_or_slugs) or is_list(slug_or_slugs) do
    aggregation = aggregation || Map.get(@aggregation_map, anomaly)
    slugs = slug_or_slugs |> List.wrap()
    get_aggregated_timeseries_data(anomaly, slugs, from, to, aggregation)
  end

  def available_aggregations(), do: @aggregations

  # Private functions

  defp slug_to_anomalies_map() do
    {:ok, asset_map} = asset_id_to_slug_map()
    {:ok, metric_map} = metric_id_to_metric_name_map()

    {query, args} = available_anomalies_query()

    ClickhouseRepo.query_reduce(query, args, %{}, fn [model_name, asset_id, metric_id], acc ->
      metric = Map.get(metric_map, metric_id)
      key = %{"metric" => metric, "model_name" => model_name}

      with anomaly when not is_nil(anomaly) <- Map.get(@metric_and_model_to_anomaly_map, key),
           slug when not is_nil(slug) <- Map.get(asset_map, asset_id) do
        Map.update(acc, slug, [%{metric: metric, anomalies: [anomaly]}], fn list ->
          [%{metric: metric, anomalies: [anomaly]} | list]
        end)
      else
        _ -> acc
      end
    end)
  end

  defp get_aggregated_timeseries_data(anomaly, slugs, from, to, aggr)
       when is_list(slugs) and length(slugs) > 20 do
    result =
      Enum.chunk_every(slugs, 20)
      |> Sanbase.Parallel.map(&get_aggregated_timeseries_data(anomaly, &1, from, to, aggr),
        timeout: 25_000,
        max_concurrency: 8,
        ordered: false
      )
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.flat_map(&elem(&1, 1))

    {:ok, result}
  end

  defp get_aggregated_timeseries_data(anomaly, slugs, from, to, aggr) when is_list(slugs) do
    {:ok, asset_map} = slug_to_asset_id_map()

    case Map.take(asset_map, slugs) |> Map.values() do
      [] ->
        {:ok, []}

      asset_ids ->
        {:ok, asset_id_map} = asset_id_to_slug_map()

        {query, args} = aggregated_timeseries_data_query(anomaly, asset_ids, from, to, aggr)

        ClickhouseRepo.query_transform(query, args, fn [asset_id, value] ->
          %{slug: Map.get(asset_id_map, asset_id), value: value}
        end)
    end
  end

  defp anomaly_not_available_error(anomaly) do
    %{close: close, error_msg: error_msg} = anomaly_not_available_error_details(anomaly)

    case close do
      nil -> {:error, error_msg}
      close -> {:error, error_msg <> " Did you mean '#{close}'?"}
    end
  end

  defp anomaly_not_available_error_details(anomaly) do
    %{
      close: Enum.find(@anomalies_mapset, &(String.jaro_distance(anomaly, &1) > 0.8)),
      error_msg: "The anomaly '#{anomaly}' is not supported or is mistyped."
    }
  end
end
