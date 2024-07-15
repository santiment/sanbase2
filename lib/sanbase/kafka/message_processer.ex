defmodule Sanbase.Kafka.MessageProcessor do
  alias Sanbase.Clickhouse.MetricAdapter.FileHandler

  def handle_messages(messages) do
    Enum.each(messages, &handle_message/1)
  end

  def handle_message(%{value: value, topic: "sanbase_combined_metrics"}) do
    value
    |> Jason.decode!()
    |> then(fn map ->
      map
      |> Map.put("datetime", DateTime.from_unix!(map["timestamp"]))
      |> Map.put("received_at", DateTime.utc_now())
      |> Map.update!("emited_at", &DateTime.from_unix!/1)
      |> Map.update!("metadata", &Jason.decode!/1)
      |> Map.update!("metric", &(FileHandler.name_to_metric(&1) || &1))
    end)
    |> handle_metric_message()
  end

  def handle_message(_), do: :ok

  # Which of the fields are to be sent to the websocket
  @fields ["datetime", "slug", "metric", "value", "metadata"]

  defp handle_metric_message(
         %{"table" => "asset_prices_stream_to_kafka_mv", "metric" => metric} = map
       ) do
    data = Map.take(map, @fields)

    for topic <- ["metrics:price", "metrics:all", "metrics:#{metric}"] do
      SanbaseWeb.Endpoint.broadcast!(topic, "metric_data", data)
    end
  end

  defp handle_metric_message(%{"table" => _table, "metric" => metric} = map) do
    data = Map.get(map, @fields)

    for topic <- ["metrics:all", "metrics:#{metric}"] do
      SanbaseWeb.Endpoint.broadcast!(topic, "metric_data", data)
    end
  end

  defp handle_metric_message(_), do: :ok
end
