defmodule Sanbase.InMemoryKafka.Producer do
  @moduledoc ~s"""
  This modulue is used by default in dev and test environments so there is no
  need for a Kafka node to be connected. It is implemented as an Agent that has
  different topics representned as fields in a map data structure.

  A function for testing purposes `get_state/{0,1}` is provided additionally
  that is not defined by the behaviour.
  """

  use Agent

  @kafka_producer :test_kafka_in_memory_producer

  def start_link() do
    Agent.start_link(fn -> %{} end, name: @kafka_producer)
  end

  def produce_sync(producer \\ @kafka_producer, topic, data) do
    Agent.update(
      producer,
      fn state ->
        Map.update(state, topic, List.wrap(data), fn topic_data ->
          List.wrap(data) ++ topic_data
        end)
      end,
      30_000
    )
  end

  def get_state(producer \\ @kafka_producer) do
    Agent.get(producer, & &1)
  end

  def clear_state(producer \\ @kafka_producer) do
    Agent.update(producer, fn _ -> %{} end)
  end
end
