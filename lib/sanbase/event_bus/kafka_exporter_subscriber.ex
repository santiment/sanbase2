defmodule Sanbase.EventBus.KafkaExporterSubscriber do
  @moduledoc """
  Export all the event bus events to a kafka topic for long-term persistence.
  """
  use GenServer

  def topics(), do: [".*"]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def init(opts) do
    {:ok, opts}
  end

  def process({_topic, _id} = event_shadow) do
    GenServer.cast(__MODULE__, event_shadow)
    :ok
  end

  def handle_cast({topic, id} = event_shadow, state) do
    case EventBus.fetch_event(event_shadow) do
      %{} = event ->
        event = restructure_event(event)
        kv_tuple = {event.id, Jason.encode!(event)}

        :ok =
          Sanbase.KafkaExporter.persist_async(
            kv_tuple,
            :sanbase_event_bus_kafka_exporter
          )

      nil ->
        {:noreply, state}
    end

    :ok = EventBus.mark_as_completed({__MODULE__, topic, id})

    {:noreply, state}
  end

  defp restructure_event(event) do
    event = event |> Map.from_struct()

    # Copy the event_type and user_id (if exists) to the top level for
    # easier filtering on these 2 fields when the kafka topic is consumed in CH
    event
    |> Map.merge(%{
      event_type: Map.fetch!(event.data, :event_type),
      user_id: Map.get(event.data, :user_id)
    })
  end
end
