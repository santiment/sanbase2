defmodule Sanbase.TestKafkaProducer do
  @behaviour SanExporterEx.ProducerBehaviour

  @kafka_producer :test_kafka_in_memory_producer

  @impl true
  def init(_) do
    {:ok, _} = Agent.start_link(fn -> %{} end, name: @kafka_producer)
    :ok
  end

  @impl true
  def send_data(topic, data) do
    Agent.update(@kafka_producer, fn state ->
      Map.update(state, topic, data, fn topic_data -> data ++ topic_data end)
    end)
  end

  @impl true
  def send_data_async(topic, data) do
    {:ok, _} = Task.start(fn -> send_data(topic, data) end)
    :ok
  end

  def get_state() do
    Agent.get(@kafka_producer, & &1)
  end
end
