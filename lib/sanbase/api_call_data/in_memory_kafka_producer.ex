defmodule Sanbase.InMemoryKafka.Producer do
  @moduledoc ~s"""
  In-memory implementation of the SanExporterEx.ProduxerBehaviour used in dev
  and test environments.

  This modulue is used by default in dev and test environments so there is no
  need for a Kafka node to be connected. It is implemented as an Agent that has
  different topics representned as fields in a map data structure.

  A function for testing purposes `get_state/{0,1}` is provided additionally
  that is not defined by the behaviour.
  """

  use Agent

  @behaviour SanExporterEx.ProducerBehaviour

  @kafka_producer :test_kafka_in_memory_producer

  def start_link(_initial_value) do
    Agent.start_link(fn -> %{} end, name: @kafka_producer)
  end

  @impl SanExporterEx.ProducerBehaviour
  def send_data(producer \\ @kafka_producer, topic, data) do
    Agent.update(producer, fn state ->
      Map.update(state, topic, List.wrap(data), fn topic_data ->
        List.wrap(data) ++ topic_data
      end)
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
