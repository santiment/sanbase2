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

  require Application

  defmodule InvalidEventError do
    defexception [:message]
  end

  @topics [
    :alert_events,
    :billing_events,
    :comment_topic,
    :insight_events,
    :invalid_events,
    :user_events,
    :watchlist_events
  ]

  @subscribers [
    __MODULE__.KafkaExporterSubscriber,
    __MODULE__.UserEventsSubscriber,
    __MODULE__.BillingEventSubscriber
  ]

  def children(), do: @subscribers

  def init() do
    for topic <- @topics, do: EventBus.register_topic(topic)
    for subscriber <- @subscribers, do: EventBus.subscribe({subscriber, subscriber.topics()})
  end

  def notify(params) do
    # In case the event is not valid, in prod this will rewrite the params so
    # the event is emitted in a special invalid_events topic. In dev/test the
    # behavior is to raise so errors are catched straight away. Invalid events
    # should not be emitted at all but they can slip in without good testing
    # and in this case prod should not break
    params =
      case Sanbase.EventBus.EventValidation.valid?(params.data) do
        true ->
          params

        false ->
          handle_invalid_event(params)
      end

    params =
      params
      |> Map.merge(%{
        id: Map.get(params, :id, UUID.uuid4()),
        topic: Map.fetch!(params, :topic),
        transaction_id: Map.get(params, :transaction_id),
        error_topic: Map.fetch!(params, :topic)
      })

    EventSource.notify params do
      Map.fetch!(params, :data)
    end
  end

  case Application.compile_env(:sanbase, :env) do
    :prod ->
      defp handle_invalid_event(params) do
        # Replace the topic with the invalid events topic so the other topics
        # always contain valid events. Also put the original topic in the data
        params
        |> put_in([:data, :original_topic], params.topic)
        |> Map.put(:topic, :invalid_events)
      end

    _ ->
      defp handle_invalid_event(params) do
        raise(
          InvalidEventError,
          message: "Invalid event submitted: #{inspect(params)}"
        )
      end
  end
end
