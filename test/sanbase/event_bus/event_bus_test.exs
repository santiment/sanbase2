defmodule Sanbase.EventBusTest do
  use ExUnit.Case, async: true

  defmodule EventBusTestSubscriber do
    def process({_topic, _id} = event_shadow) do
      event = EventBus.fetch_event(event_shadow)
      Process.send(:__internal_event_test_process_name_given__, event.data.message, [])
      EventBus.mark_as_completed(event)

      :ok
    end
  end

  setup do
    EventBus.register_topic(:test_events)
    EventBus.subscribe({EventBusTestSubscriber, [".*"]})

    []
  end

  test "emit and process event" do
    # Register a name and use it. If the event contains a pid, the Jason encoder
    # will fail encoding it to json
    Process.register(self(), :__internal_event_test_process_name_given__)

    for i <- 1..50 do
      Sanbase.EventBus.notify(%{
        topic: :test_events,
        data: %{message: "ping#{i}", __internal_valid_event__: true}
      })
    end

    for i <- 1..50 do
      msg = "ping#{i}"
      assert_receive(^msg, 1000)
    end
  end
end
