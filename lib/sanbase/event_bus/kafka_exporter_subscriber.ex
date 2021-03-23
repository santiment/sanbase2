defmodule Sanbase.EventBus.KafkaExporterSubscriber do
  @moduledoc """
  Export all the event bus events to a kafka topic for long-term persistence.
  """
  use GenServer

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
        :ok =
          Sanbase.KafkaExporter.persist_async(
            {event.id, Jason.encode!(event)},
            :sanbase_event_bus_kafka_exporter
          )

      nil ->
        {:noreply, state}
    end

    :ok = EventBus.mark_as_completed({__MODULE__, topic, id})

    {:noreply, state}
  end
end
