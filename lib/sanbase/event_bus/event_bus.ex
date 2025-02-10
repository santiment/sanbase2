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
    @moduledoc false
    defexception [:message]
  end

  @topics [
    :alert_events,
    :billing_events,
    :comment_topic,
    :insight_events,
    :invalid_events,
    :user_events,
    :watchlist_events,
    :metric_registry_events
  ]

  @subscribers [
    __MODULE__.KafkaExporterSubscriber,
    __MODULE__.UserEventsSubscriber,
    __MODULE__.BillingEventSubscriber,
    __MODULE__.MetricRegistrySubscriber,
    __MODULE__.NotificationsSubscriber
  ]

  def children, do: @subscribers

  def init do
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
      if Sanbase.EventBus.EventValidation.valid?(params.data) do
        params
      else
        handle_invalid_event(params)
      end

    params =
      Map.merge(params, %{
        id: Map.get(params, :id, UUID.uuid4()),
        topic: Map.fetch!(params, :topic),
        transaction_id: Map.get(params, :transaction_id),
        error_topic: Map.fetch!(params, :topic)
      })

    EventSource.notify params do
      Map.fetch!(params, :data)
    end
  end

  @doc ~s"""
  Invoke this function from the subscriber module instead of direclty handling the event.
  The handle_fun/0 is the function that does the actual handling of the event.
  The purpose of this function is to wrap the actual handling in logic that decides
  if the handler should be called, or skipped and direclty marked as completed.

  In cases where the skip is required is when we distribute the same event to each node
  in the cluster. In some cases the event need to be handled on all the other nodes
  just by one of the subscribers, not all, as this can lead to duplicated notifications send,
  duplicated records in kafka, etc.

  To mark that the event needs to be processed by only some of the subscribers, emit the event
  in the following way

    Registry.EventEmitter.emit_event({:ok, maybe_struct}, :update_metric_registry, %{
      __only_process_by__: [Sanbase.EventBus.MetricRegistrySubscriber]
    })

  Note that in order for this to work, the emitter must propagate the args, usually by building some
  event map from the arguments and then piping it into `|>Map.merge(args)`
  """
  @spec handle_event(module(), map(), map(), state, (-> state)) :: state when state: any()
  def handle_event(module, event, event_shadow, state, handle_fun) when is_function(handle_fun, 0) do
    case event do
      %{data: %{__only_process_by__: list}} ->
        if module in list do
          handle_fun.()
        else
          # If __only_process_by__ is set and the module is not part of it,
          # do not process this event, but direclty mark it as processed and
          # return the state unchanged
          EventBus.mark_as_completed({module, event_shadow})

          state
        end

      _ ->
        handle_fun.()
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
