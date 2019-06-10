defmodule Sanbase.ApiCallDataExporter do
  @moduledoc ~s"""
  Module for persisting API calls data to Kafka.

  The module exposes one function that should be used - `persist/1`.
  This functions adds the data to an internal buffer that is flushed
  every `kafka_flush_timeout` seconds or when the buffer is big enough.

  The exporter cannot send data more than once every 1 second so the this
  GenServer cannot die too often and crash its supervisor
  """

  use GenServer

  require Logger
  require Sanbase.Utils.Config, as: Config

  @producer Config.get(:producer, SanExporterEx.Producer)

  @typedoc ~s"""
  A map that represents the API call data that will be persisted.
  """
  @type api_call_data :: %{
          timestamp: non_neg_integer() | nil,
          query: String.t() | nil,
          status_code: non_neg_integer(),
          has_graphql_errors: boolean() | nil,
          user_id: non_neg_integer() | nil,
          auth_method: :atom | nil,
          api_token: String.t() | nil,
          remote_ip: String.t(),
          user_agent: String.t(),
          duration_ms: non_neg_integer() | nil,
          san_tokens: float() | nil
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
          | {:can_send_after_interval, non_neg_integer()}
        ]

  @spec start_link(options) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
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
  Asynchronously add the API call data to the buffer.

  It will be sent no longer than `kafka_flush_timeout` seconds later. The data
  is pushed to an internal buffer that is then send at once to Kafka.
  """
  @spec persist(api_call_data | [api_call_data]) :: :ok
  @spec persist(pid() | atom(), api_call_data | [api_call_data]) :: :ok
  def persist(exporter \\ __MODULE__, api_call_data) do
    GenServer.cast(exporter, {:persist, api_call_data})
  end

  @doc ~s"""
  Send all available data in the buffers before shutting down.

  The ApiCallRecorder should be started before the Endpoint in the supervison tree.
  This means that when shutting down it will be stopped after the Endpoint so
  all API call data will be stored in Kafka and no more API calls are exepcted
  """
  def terminate(_reason, state) do
    Logger.info(
      "Terminating the ApiCallExporter. Sending #{length(state.data)} API Call events to Kafka."
    )

    send_data(state.data, state)
    :ok
  end

  @spec handle_cast({:persist, api_call_data | [api_call_data]}, state) :: {:noreply, state}
        when state: map()
  def handle_cast(
        {:persist, api_call_data},
        state
      ) do
    data = api_call_data |> List.wrap() |> Enum.map(&{"", Jason.encode!(&1)})
    new_messages_length = length(data)

    case state.size + new_messages_length >= state.buffering_max_messages do
      true ->
        :ok = send_data(data ++ state.data, state)

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
    :ok = send_data(state.data, state)

    Process.send_after(self(), :flush, state.kafka_flush_timeout)
    {:noreply, %{state | data: [], size: 0}}
  end

  defp send_data([], _), do: :ok
  defp send_data(nil, _), do: :ok

  defp send_data(data, %{topic: topic, can_send_after: can_send_after, size: size}) do
    Sanbase.DateTimeUtils.sleep_until(can_send_after)
    Logger.info("Sending #{size} API Call events to Kafka.")
    @producer.send_data(topic, data)
  end
end
