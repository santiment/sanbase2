defmodule Sanbase.EventBus.NoopSubscriber do
  @moduledoc """
  A no-op EventBus subscriber used only in tests.

  Subscribes to all topics so the EventBus does not emit a warning about
  topics having no subscribers when the other subscribers are disabled.
  """
  use GenServer

  def topics(), do: [".*"]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def init(opts) do
    {:ok, opts}
  end

  def process({_topic, _id} = event_shadow) do
    spawn(fn -> EventBus.mark_as_completed({__MODULE__, event_shadow}) end)
    :ok
  end
end
