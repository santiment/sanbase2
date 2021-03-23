defmodule Sanbase.EventBus.PaymentSubscriber do
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
    event_type = event.data.event_type

    state = handle_event(event_type, event, event_shadow, state)
    {:noreply, state}
  end

  defp handle_event(:payment_success, _event, event_shadow, state) do
    :ok = EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(:payment_fail, _event, event_shadow, state) do
    :ok = EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(:cancel_subscription, _event, event_shadow, state) do
    :ok = EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(:new_subscription, _event, event_shadow, state) do
    :ok = EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(:apply_promocode, _event, event_shadow, state) do
    :ok = EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end
end
