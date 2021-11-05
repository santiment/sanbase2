defmodule Sanbase.EventBusTest do
  use ExUnit.Case, async: false
  import Sanbase.TestHelpers, only: [wait_event_bus_subscriber: 1]

  defmodule EventBusTestSubscriber do
    @receiver_name :__internal_event_test_process_name_given__
    def receiver_name(), do: @receiver_name

    def process({_topic, _id} = event_shadow) do
      event = EventBus.fetch_event(event_shadow)

      Process.send(@receiver_name, event.data.message, [])
      EventBus.mark_as_completed(event)

      :ok
    end
  end

  setup do
    test_events_topic = :test_events
    :ok = EventBus.register_topic(test_events_topic)
    :ok = EventBus.subscribe({EventBusTestSubscriber, ["test_events"]})

    on_exit(fn ->
      EventBus.unsubscribe(EventBusTestSubscriber)
      EventBus.unregister_topic(test_events_topic)
    end)

    # register_topic is done via GenServer.call/2, but EventBus.subscribe is
    # done via GenServer.cast/2. Adding a small wait loop to make sure the test
    # starts only after the subscriber is properly established.
    wait_event_bus_subscriber(test_events_topic)

    :ok
  end

  test "emit and process event" do
    # Register a name and use it. If the event contains a pid, the Jason encoder
    # will fail encoding it to json
    Process.register(self(), EventBusTestSubscriber.receiver_name())

    for i <- 1..50 do
      Sanbase.EventBus.notify(%{
        topic: :test_events,
        data: %{event_type: :test_event, message: "ping#{i}", __internal_valid_event__: true}
      })
    end

    for i <- 1..50 do
      msg = "ping#{i}"
      assert_receive(^msg, 1000)
    end
  end
end
