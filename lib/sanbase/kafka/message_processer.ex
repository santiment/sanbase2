defmodule Sanbase.Kafka.MessageProcessor do
  @name_to_metric_map Sanbase.Clickhouse.MetricAdapter.FileHandler.name_to_metric_map()
  def handle_messages(messages) do
    Enum.each(messages, &handle_message/1)
  end

  def handle_message(%{value: value, topic: "sanbase_combined_metrics_stream"}) do
    value
    |> Jason.decode!()
    |> then(fn map ->
      map
      |> Map.put("datetime", DateTime.from_unix!(map["timestamp"]))
      |> Map.put("received_at", DateTime.utc_now())
      |> Map.update!("emited_at", &DateTime.from_unix!/1)
      |> Map.update!("metadata", &Jason.decode!/1)
      |> Map.update!("metric", &(Map.get(@name_to_metric_map, &1) || &1))
    end)
    |> handle_metric_message()
  end

  defp handle_metric_message(
         %{"table" => "asset_prices_stream_to_kafka_mv", "metric" => metric} = map
       ) do
    data = Map.get(map, ["datetime", "slug", "metric", "value"])

    for topic <- ["metrics:price", "metrics:all", "metrics:#{metric}"] do
      SanbaseWeb.Endpoint.broadcast_from!(self(), topic, "metric_data", data)
    end
  end

  defp handle_metric_message(%{"table" => _table, "metric" => metric} = map) do
    data = Map.get(map, ["datetime", "slug", "metric", "value"])

    for topic <- ["metrics:all", "metrics:#{metric}"] do
      SanbaseWeb.Endpoint.broadcast_from!(self(), topic, "metric_data", data)
    end
  end

  defp handle_metric_message(_), do: :ok
end
