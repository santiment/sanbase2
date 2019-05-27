defmodule Sanbase.ApiCallDataExporter do
  @moduledoc ~s"""
  Module for persisting API calls data to Kafka.

  The module exposes one function that should be used - `persist/1`.
  This functions adds the data to an internal buffer that is flushed
  every `kafka_flush_timeout` seconds or when the buffer is big enough.
  """

  use GenServer

  require Sanbase.Utils.Config, as: Config
  @producer Config.get(:api_call_data_kafka_producer, SanExporterEx.Producer)

  @typedoc ~s"""
  A map that represents the API call data that will be persisted.
  """
  @type api_call_data :: %{
          timestamp: non_neg_integer(),
          query: String.t(),
          status_code: non_neg_integer(),
          user_id: non_neg_integer(),
          auth_method: :atom,
          api_token: String.t(),
          remote_ip: String.t(),
          user_agent: String.t(),
          duration_ms: non_neg_integer(),
          san_tokens: float()
        }

  @typedoc ~s"""
  Options that describe to which kafka topic and how often to send the batches.
  These options do not describe the connection
  """
  @type options :: [
          {:name, atom()}
          | {:topic, String.t()}
          | {:kafka_flush_timeout, non_neg_integer()}
          | {:buffering_max_messages, non_neg_integer()}
        ]

  @spec start_link(options) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec init(options) :: {:ok, state} when state: map()
  def init(opts) do
    kafka_flush_timeout = Keyword.get(opts, :kafka_flush_timeout, 5000)
    buffering_max_messages = Keyword.get(opts, :buffering_max_messages, 5000)
    Process.send_after(self(), :flush, kafka_flush_timeout)

    {:ok,
     %{
       topic: Keyword.fetch!(opts, :topic),
       data: [],
       size: 0,
       kafka_flush_timeout: kafka_flush_timeout,
       buffering_max_messages: buffering_max_messages
     }}
  end

  @doc ~s"""
  Assynchronously add the API call data to the buffer.

  It will be sent no longer than `kafka_flush_timeout` seconds later. The data
  is pushed to an internal buffer that is then send at once to Kafka.
  """
  @spec persist(api_call_data | [api_call_data]) :: :ok
  @spec persist(pid() | atom(), api_call_data | [api_call_data]) :: :ok
  def persist(exporter \\ __MODULE__, api_call_data) do
    # Log so it's seen in Kibana
    # Logger.info(api_call_data)
    GenServer.cast(exporter, {:persist, api_call_data})
  end

  @doc ~s"""
  Send all available data in the buffers before shutting down.

  The ApiCallRecorder should be started before the Endpoin in the supervison tree.
  This means that when shutting down it will be stopped after the Endpoint so
  all API call data will be stored in Kafka and no more API calls are exepcted
  """
  def terminate(_reason, state) do
    _ = send_data(state.topic, state.data)
    :ok
  end

  @spec handle_cast({:persist, api_call_data | [api_call_data]}, state) :: {:noreply, state}
        when state: map()
  def handle_cast(
        {:persist, api_call_data},
        %{size: size, buffering_max_messages: bms} = state
      )
      when size >= bms - 1 do
    data = api_call_data |> List.wrap() |> Enum.map(&Jason.encode!/1)

    :ok = send_data(state.topic, data ++ state.data)
    {:noreply, %{state | data: [], size: 0}}
  end

  def handle_cast({:persist, api_call_data}, state) do
    data = api_call_data |> List.wrap() |> Enum.map(&Jason.encode!/1)
    {:noreply, %{state | data: data ++ state.data, size: state.size + 1}}
  end

  def handle_info(:flush, state) do
    :ok = send_data(state.topic, state.data)
    Process.send_after(self(), :flush, state.kafka_flush_timeout)
    {:noreply, %{state | data: [], size: 0}}
  end

  defp send_data(topic, data) do
    @producer.send_data(topic, data)
  end
end
