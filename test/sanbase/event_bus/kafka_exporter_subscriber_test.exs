defmodule Sanbase.EventBus.KafkaExporterSubscriberTest do
  use Sanbase.DataCase, async: false
  import Sanbase.Factory

  test "check kafka message format" do
    Sanbase.InMemoryKafka.Producer.clear_state()

    user = insert(:user)
    Process.put(:__kafka_exporter_async_as_sync__, true)

    Sanbase.Accounts.EventEmitter.emit_event({:ok, user}, :register_user, %{login_origin: :google})

    # Wait a little bit because there are 2 GenServer.cast/2 invokations
    Process.sleep(100)

    event_bus_data = Sanbase.InMemoryKafka.Producer.get_state()["sanbase_event_bus"]

    assert length(event_bus_data) == 1
    assert [{_key, value}] = event_bus_data

    user_id = user.id

    assert %{
             "data" => %{
               "event_type" => "register_user",
               "login_origin" => "google",
               "user_id" => ^user_id
             },
             "event_type" => "register_user",
             "id" => _,
             "initialized_at" => _,
             "occurred_at" => _,
             "source" => "Sanbase.EventBus",
             "topic" => "user_events",
             "transaction_id" => nil,
             "ttl" => nil,
             "user_id" => ^user_id
           } = Jason.decode!(value)
  end
end
