defmodule Sanbase.EventBus.EventEmitter.Behaviour do
  @moduledoc false
  @type entity :: any()
  @type event_type :: atom()
  @type extra_args :: map()

  @doc """
  Invoked in order to emit and event and push it to the Event Bus.

  The emit_event function always should return its first argument as the result
  as it should be able to be put in a pipeline without any changes.

  The first argument is the main entity that is used in the event and that is
  returned so the pipeline where emit_event/3 is used can continue. It could be
  a single struct, an :ok|:error tuple, etc.

  The second argument is the event type itself. It is used to determine what the
  event is, in what topic it should be posted and how to build the data for it.

  The third argument is a free-form map that holds any extra information needed
  that is not obtainable from the entity itself. For example, when a user logs
  in, the extra args holds the origin of the login: email, metamask, google,
  twitter, etc.
  """
  @callback emit_event(entity, event_type, extra_args) :: entity
end
