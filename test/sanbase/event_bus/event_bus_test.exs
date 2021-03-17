defmodule Sanbase.EventBusTest do
  use ExUnit.Case, async: true

  defmodule EventBusTestSubscriber do
    def process({_topic, _id} = event_shadow) do
      event = EventBus.fetch_event(event_shadow)
      send(event.data.pid, event.data.message)
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
    Sanbase.EventBus.notify(%{
      topic: :test_events,
      data: %{pid: self(), message: "ping1", __internal_valid_event__: true}
    })

    Sanbase.EventBus.notify(%{
      topic: :test_events,
      data: %{pid: self(), message: "ping2", __internal_valid_event__: true}
    })

    Sanbase.EventBus.notify(%{
      topic: :test_events,
      data: %{pid: self(), message: "ping3", __internal_valid_event__: true}
    })

    assert_receive "ping1"
    assert_receive "ping2"
    assert_receive "ping3"
  end
end
