defmodule Sanbase.EventBus.KafkaExporterSubscriberTest do
  use Sanbase.DataCase, async: false
  import Sanbase.Factory
  import Mox

  setup :set_mox_from_context
  setup :verify_on_exit!

  test "check kafka message format" do
    expect(Sanbase.Email.MockMailjetApi, :subscribe, fn _, _ -> :ok end)
    # NOTE: This test is consistently failing for unknown reasons. Remove it for
    # now to unblock the other PRs and it will be revised later

    Sanbase.InMemoryKafka.Producer.clear_state()

    user = insert(:user)

    Sanbase.Accounts.EventEmitter.emit_event({:ok, user}, :register_user, %{
      login_origin: :google
    })

    # # Do this otherwise the get_state/0 does not have the results stored. The logic
    # # must pass from emitting to the kafka subscriber which exports the events.
    Process.sleep(500)

    event_bus_data = Sanbase.InMemoryKafka.Producer.get_state()["sanbase_event_bus"] || []

    assert [{_key, value} | _] = event_bus_data

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
