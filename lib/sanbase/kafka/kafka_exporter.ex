defmodule Sanbase.KafkaExporter do
  @moduledoc ~s"""
  Module for persisting any data to Kafka.

  The module exposes one function that should be used - `persist/1`.
  This functions adds the data to an internal buffer that is flushed
  every `kafka_flush_timeout` milliseconds or when the buffer is big enough.

  The exporter cannot send data more than once every 1 second so the
  GenServer cannot die too often and crash its supervisor
  """

  use GenServer

  require Logger

  @producer Application.compile_env(:sanbase, [Sanbase.KafkaExporter, :producer])

  @type data :: {String.t(), String.t()}
  @type result :: :ok | {:error, String.t()}

  @typedoc ~s"""
  Options that describe to which kafka topic and how often to send the batches.
  These options do not describe the connection
  """
  @type options :: [
          {:name, atom()}
          | {:topic, String.t()}
          | {:kafka_flush_timeout, non_neg_integer()}
          | {:buffering_max_messages, non_neg_integer()}
          | {:can_send_after_interval, non_neg_integer()}
        ]

  @spec start_link(options) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(opts) do
    %{
      id: Keyword.fetch!(opts, :id),
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @spec init(options) :: {:ok, state} when state: map()
  def init(opts) do
    kafka_flush_timeout = Keyword.get(opts, :kafka_flush_timeout, 30_000)
    buffering_max_messages = Keyword.get(opts, :buffering_max_messages, 1000)
    can_send_after_interval = Keyword.get(opts, :can_send_after_interval, 1000)
    Process.send_after(self(), :flush, kafka_flush_timeout)

    {:ok,
     %{
       topic: Keyword.fetch!(opts, :topic),
       data: [],
       size: 0,
       kafka_flush_timeout: kafka_flush_timeout,
       buffering_max_messages: buffering_max_messages,
       can_send_after_interval: can_send_after_interval,
       can_send_after: DateTime.utc_now() |> DateTime.add(can_send_after_interval, :millisecond)
     }}
  end

  @doc ~s"""
  Asynchronously add data to be exported to the buffer.

  It will be sent no longer than `kafka_flush_timeout` milliseconds later. The data
  is pushed to an internal buffer that is then send at once to Kafka.
  """

  @spec persist_async(data | [data], pid() | atom()) :: :ok
  def persist_async(data, exporter) do
    GenServer.cast(exporter, {:persist, data})
  end

  @spec persist_sync(data | [data], pid() | atom()) :: result
  def persist_sync(data, exporter, timeout \\ 60_000) do
    GenServer.call(exporter, {:persist, data}, timeout)
  end

  def send_data_to_topic_from_current_process(data, topic) do
    send_data_immediately(data, %{topic: topic, size: length(data)})
  end

  def flush(exporter \\ __MODULE__) do
    GenServer.call(exporter, :flush, 30_000)
  end

  @doc ~s"""
  Send all available data in the buffers before shutting down.

  The data recorder should be started before the Endpoint in the supervison tree.
  This means that when shutting down it will be stopped after the Endpoint so
  all data will be stored in Kafka and no more data is expected.
  """
  def terminate(_reason, state) do
    Logger.info(
      "Terminating the KafkaExporter. Sending #{length(state.data)} events to kafka topic: #{state.topic}"
    )

    send_data(state.data, state)
    :ok
  end

  @spec handle_call({:persist, data | [data]}, any(), state) :: {:reply, result, state}
        when state: map()
  def handle_call({:persist, data}, _from, state) do
    data = List.wrap(data)

    send_data_result =
      (data ++ state.data)
      |> send_data_immediately(%{state | size: state.size + length(data)})

    {:reply, send_data_result, %{state | data: [], size: 0}}
  end

  def handle_call(:flush, _from, state) do
    send_data_immediately(state.data, state)
    {:reply, :ok, %{state | data: [], size: 0}}
  end

  @spec handle_cast({:persist, data | [data]}, state) :: {:noreply, state}
        when state: map()
  def handle_cast({:persist, data}, state) do
    data = List.wrap(data)
    new_messages_length = length(data)

    case state.size + new_messages_length >= state.buffering_max_messages do
      true ->
        :ok = send_data(data ++ state.data, %{state | size: state.size + new_messages_length})

        {:noreply,
         %{
           state
           | data: [],
             size: 0,
             can_send_after:
               DateTime.utc_now() |> DateTime.add(state.can_send_after_interval, :millisecond)
         }}

      false ->
        {:noreply, %{state | data: data ++ state.data, size: state.size + new_messages_length}}
    end
  end

  def handle_info(:flush, state) do
    send_data(state.data, state)

    Process.send_after(self(), :flush, state.kafka_flush_timeout)
    {:noreply, %{state | data: [], size: 0}}
  end

  defp send_data([], _), do: :ok
  defp send_data(nil, _), do: :ok

  # In case there is no wait period between sends, do not execute the sleep_until
  # at all
  defp send_data(data, %{topic: topic, can_send_after_interval: 0, size: size}) do
    Logger.info("Sending #{size} events to Kafka topic: #{topic}")
    @producer.send_data(topic, data)
  end

  defp send_data(data, %{topic: topic, can_send_after: can_send_after, size: size}) do
    Sanbase.DateTimeUtils.sleep_until(can_send_after)
    Logger.info("Sending #{size} events to Kafka topic: #{topic}")
    @producer.send_data(topic, data)
  end

  defp send_data_immediately([], _), do: :ok
  defp send_data_immediately(nil, _), do: :ok

  defp send_data_immediately(data, %{topic: topic, size: size}) do
    Logger.info("Sending #{size} events to Kafka topic: #{topic}")
    @producer.send_data(topic, data)
  end
end
