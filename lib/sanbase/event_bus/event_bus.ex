defmodule Sanbase.EventBus do
  @moduledoc """
  The Event Bus is a mechanism that allows different components to communicate
  with each other without knowing about eachother.

  The Event Bus allows to decouple the creation of an event from the processing
  of that same event. A component sends events to the Event Bus without knowing
  what component will process these event or how many components will process
  the event. The components processing the events do not know and do not need to
  know who emitted the event.

  The event bus implementation lends itself into separating into two main
  component types - emitter and subscriber. The emitter sends event to topics
  and the subscriber listens on some or all topics and processes the messages.

  An emitter is every module that invokes the Sanbase.EventBus.notify/1 function.
  In order to emit an event, all a module needs is to know a valid topic name
  and valid event structure. The valid event structure are those that are
  recognized by the Sanbase.EventValidation.valid?/1 function.

  The subscribers should subscribe to a list of topics by invoking the
  EventBus.subscribe.subscribe/1 function like this:
  EventBus.subscribe({Sanbase.EventBus.KafkaExporterSubscriber, [".*"]}). The
  subscribers should implement a process/1 function that accepts an event_shadow
  and processes the event. Most often the subscriber is a GenServer and the
  process/1 function just casts the event shadow so it is processed asynchronously.
  """

  use EventBus.EventSource

  defmodule InvalidEventError do
    defexception [:message]
  end

  @topics [:user_events, :watchlist_events, :alert_events, :insight_events, :payment_events]
  @subscribers [
    __MODULE__.KafkaExporterSubscriber,
    __MODULE__.UserEventsSubscriber,
    __MODULE__.PaymentSubscriber
  ]
  def init() do
    for topic <- @topics, do: EventBus.register_topic(topic)
    for subscriber <- @subscribers, do: EventBus.subscribe({subscriber, subscriber.topics()})
  end

  def notify(params) do
    params =
      params
      |> Map.merge(%{
        id: Map.get(params, :id, Ecto.UUID.generate()),
        topic: Map.fetch!(params, :topic),
        transaction_id: Map.get(params, :transaction_id),
        error_topic: Map.fetch!(params, :topic)
      })

    EventSource.notify params do
      data = Map.fetch!(params, :data)

      case Sanbase.EventBus.EventValidation.valid?(data) do
        true ->
          data

        false ->
          raise(
            InvalidEventError,
            message: "Invalid event submitted: #{inspect(params)}"
          )
      end
    end
  end
end
