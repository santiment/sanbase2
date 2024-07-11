defmodule Sanbase.Kafka.Implementation.Producer do
  @client_name :kafka_client

  require Logger

  def produce_sync(topic, list) when is_list(list) do
    if Enum.any?(list, &(not match?({<<_::binary>>, _}, &1))) do
      raise ArgumentError, "Invalid list format. Each element should be a tuple {key, value}"
    end

    produce_list_sync(topic, list)
  end

  defp produce_list_sync(topic, messages_list) do
    Logger.debug("event#produce_list topic=#{topic}")

    messages_list
    |> add_timestamp()
    |> group_by_partition(topic)
    |> case do
      messages = %{} ->
        produce_list_to_topic(topic, messages)

      {:error, reason} ->
        Logger.warning("Error while grouping by partition #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp produce_list_to_topic(topic, %{} = partition_to_messages_map) do
    partition_to_messages_map
    |> Enum.reduce_while(:ok, fn {partition, messages}, :ok ->
      Logger.debug("[KafkaProducer/produce_list_to_topic] topic=#{topic} partition=#{partition}")

      # As `messages` is a batch, the `key` argument is used only as argument to the partitioner
      # argument. Here we are passing the partition number itself; partitioner would
      # be if function, :random or :hash is passed as the third argument.

      case :brod.produce_sync(@client_name, topic, partition, _key = "ignored", messages) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  # Add a timestamp to each message in the list
  defp add_timestamp(list) do
    time = System.system_time(:millisecond)

    list
    |> Enum.map(fn {key, value} ->
      {time, key, value}
    end)
  end

  # Transform a list of messages like [{key, value}, {key2, value2}]
  # to a map like %{0 => [{key_value}], 1 => [{key2, value2}]} where the
  # keys are the partitions
  defp group_by_partition(messages, topic) do
    with {:ok, partitions_count} <- get_partitions_count(topic) do
      messages
      |> Enum.group_by(fn {_timestamp, key, _message} ->
        choose_partition(partitions_count, key)
      end)
    end
  end

  # Returns the number of partitions for the given topic
  # The data is stored in persistent_term to reduce calls to kafka
  defp get_partitions_count(topic) do
    case :persistent_term.get({:partitions_count, topic}, :not_stored) do
      :not_stored ->
        case :brod.get_partitions_count(@client_name, topic) do
          {:ok, partitions_count} ->
            :persistent_term.put({:partitions_count, topic}, {:ok, partitions_count})
            {:ok, partitions_count}

          {:error, error} ->
            {:error, error}
        end

      {:ok, partitions_count} ->
        {:ok, partitions_count}
    end
  end

  defp choose_partition(partitions_count, key) do
    :crypto.hash(:md5, key)
    |> :erlang.binary_to_list()
    |> Enum.sum()
    |> rem(partitions_count)
  end
end
