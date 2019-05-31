defmodule Sanbase.InMemoryKafka.Producer do
  use Agent

  @behaviour SanExporterEx.ProducerBehaviour

  @kafka_producer :test_kafka_in_memory_producer

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: @kafka_producer)
  end

  @impl SanExporterEx.ProducerBehaviour
  @spec send_data(any, any) :: :ok
  def send_data(producer \\ @kafka_producer, topic, data) do
    Agent.update(producer, fn state ->
      Map.update(state, topic, data, fn topic_data -> data ++ topic_data end)
    end)
  end

  @impl SanExporterEx.ProducerBehaviour
  def send_data_async(producer \\ @kafka_producer, topic, data) do
    {:ok, _} = Task.start(fn -> send_data(producer, topic, data) end)
    :ok
  end

  def get_state(producer \\ @kafka_producer) do
    Agent.get(producer, & &1)
  end
end

defmodule Sanbase.InMemoryKafka.Supervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts)
  end

  def init(opts) do
    children = [
      {Sanbase.InMemoryKafka.Producer, opts}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
