defmodule Sanbase.EventBus.MetricRegistrySubscriber do
  @moduledoc """
  Subscribe to all events and generate notifications that will be shown on sanbase
  """
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def init(opts) do
    {:ok, opts}
  end

  def process({_topic, _id} = event_shadow) do
    GenServer.cast(__MODULE__, event_shadow)
    :ok
  end

  def handle_cast({_topic, _id} = event_shadow, state) do
    event = EventBus.fetch_event(event_shadow)
    state = handle_event(event, event_shadow, state)
    {:noreply, state}
  end

  defp handle_event(_event, event_shadow, state) do
    :ok = EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end
end
