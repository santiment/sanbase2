defmodule Sanbase.Kafka.ProducerConfigTest do
  use ExUnit.Case, async: false

  import Mock

  test "start_producer/1 passes the client's default_producer_config to brod" do
    config = [max_retries: 10, retry_backoff_ms: 1_000]
    previous = Application.get_env(:brod, :clients)
    Application.put_env(:brod, :clients, kafka_client: [default_producer_config: config])
    on_exit(fn -> Application.put_env(:brod, :clients, previous) end)

    with_mock :brod,
      start_producer: fn _client, _topic, producer_config -> {:ok, producer_config} end do
      assert Sanbase.Kafka.Implementation.Producer.start_producer("topic") == {:ok, config}
    end
  end
end
