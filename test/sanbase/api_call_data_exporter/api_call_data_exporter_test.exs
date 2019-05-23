defmodule ApiCallDataExporterTest do
  use ExUnit.Case

  setup do
    :ok = Sanbase.TestKafkaProducer.init([])
    # do not buffer message
    topic = :crypto.strong_rand_bytes(12) |> Base.encode64()
    %{topic: topic}
  end

  test "no data written when there are no api calls" do
    assert Sanbase.TestKafkaProducer.get_state() == %{}
  end

  # Setting buffering max messages to 0 sends to kafka on each `persist` call
  test "buffering max messages works", %{topic: topic} do
    {:ok, exporter_pid} =
      Sanbase.ApiCallDataExporter.start_link(
        buffering_max_messages: 0,
        kafka_flush_timeout: 10_000,
        topic: topic
      )

    data = api_call_data()
    :ok = Sanbase.ApiCallDataExporter.persist(exporter_pid, data)
    Process.sleep(100)
    state = Sanbase.TestKafkaProducer.get_state()
    assert Map.get(state, topic) == [Jason.encode!(data)]
  end

  # Setting kafka_flush_timeout to 100 flushes the buffer to kafka each 100ms
  test "kafka flush timeout works", %{topic: topic} do
    {:ok, exporter_pid} =
      Sanbase.ApiCallDataExporter.start_link(
        buffering_max_messages: 5000,
        kafka_flush_timeout: 100,
        topic: topic
      )

    data = api_call_data()
    :ok = Sanbase.ApiCallDataExporter.persist(exporter_pid, data)
    Process.sleep(100)
    state = Sanbase.TestKafkaProducer.get_state()
    assert Map.get(state, topic) == [Jason.encode!(data)]
  end

  test "batching api calls works after flush timeout time has passed", %{topic: topic} do
    {:ok, exporter_pid} =
      Sanbase.ApiCallDataExporter.start_link(
        buffering_max_messages: 5000,
        kafka_flush_timeout: 200,
        topic: topic
      )

    for _ <- 1..50, do: :ok = Sanbase.ApiCallDataExporter.persist(exporter_pid, api_call_data())

    # No data even after 50 api calls were persisted and some time has passed
    Process.sleep(100)
    state = Sanbase.TestKafkaProducer.get_state()
    assert state == %{}

    # Aftert the kafka flush timeout has been reached the data is flushed
    Process.sleep(100)
    state = Sanbase.TestKafkaProducer.get_state()
    topic_data = Map.get(state, topic)
    assert length(topic_data) == 50
  end

  test "batching api calls works after max messages number is reached", %{topic: topic} do
    {:ok, exporter_pid} =
      Sanbase.ApiCallDataExporter.start_link(
        buffering_max_messages: 500,
        kafka_flush_timeout: 100_000,
        topic: topic
      )

    for _ <- 1..600, do: :ok = Sanbase.ApiCallDataExporter.persist(exporter_pid, api_call_data())

    Process.sleep(100)
    state = Sanbase.TestKafkaProducer.get_state()
    topic_data = Map.get(state, topic)

    # buffering_max_messages has been sent, another 100 are still waiting in the exporter
    assert length(topic_data) == 500
  end

  test "trigger multiple batch sends", %{topic: topic} do
    {:ok, exporter_pid} =
      Sanbase.ApiCallDataExporter.start_link(
        buffering_max_messages: 100,
        kafka_flush_timeout: 5000,
        topic: topic
      )

    for _ <- 1..10_000,
        do: :ok = Sanbase.ApiCallDataExporter.persist(exporter_pid, api_call_data())

    Process.sleep(100)
    state = Sanbase.TestKafkaProducer.get_state()
    topic_data = Map.get(state, topic)
    assert length(topic_data) == 10_000
  end

  defp api_call_data() do
    %{
      timestamp: Timex.now() |> DateTime.to_unix(),
      query: random_query(),
      status_code: 200,
      user_id: :rand.uniform(100),
      token: :crypto.strong_rand_bytes(32) |> Base.encode64(),
      remote_ip: random_ip_v4(),
      user_agent: Faker.Internet.UserAgent.desktop_user_agent(),
      duration_ms: :rand.uniform_real() * 1000,
      san_tokens: Enum.random(200..2000)
    }
  end

  defp random_query() do
    Enum.random(["all_projects", "token_age_consumed", "history_price", "current_user"])
  end

  defp random_ip_v4() do
    octet1 = :rand.uniform(255)
    octet2 = :rand.uniform(255)
    octet3 = :rand.uniform(255)
    octet4 = :rand.uniform(255)

    "#{octet1}.#{octet2}.#{octet3}.#{octet4}"
  end
end
