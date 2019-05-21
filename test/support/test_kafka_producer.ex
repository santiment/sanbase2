defmodule Sanbase.TestKafkaProducer do
  @behaviour SanExporterEx.ProducerBehaviour

  @name :test_kafka_in_memory_exporter

  @impl true
  def init(_) do
    {:ok, _} = Agent.start_link(fn -> %{} end, name: @name)
    :ok
  end

  @impl true
  def send_data(topic, data) do
    Agent.update(@name, fn state ->
      Map.update(state, topic, [], fn topic_data -> data ++ topic_data end)
    end)
  end

  @impl true
  def send_data_async(topic, data) do
    {:ok, _} = Task.start(fn -> send_data(topic, data) end)
    :ok
  end
end
