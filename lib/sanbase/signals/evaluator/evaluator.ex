defmodule Sanbase.Signal.Evaluator do
  @moduledoc ~s"""
  A module that takes a list of triggers and returns the ones that are triggered.

  The evaluation can be executed or the values can be taken from a cache. Taking
  data from the cache respects the last triggered datetimes, the cooldown value and
  all relevat trigger settings. Some of the fields such as the distribution channel
  (email or telegram), name and description of the signal, etc. are ignored
  """

  alias Sanbase.Signal.Evaluator.Cache
  alias Sanbase.Signal.{UserTrigger, Trigger}

  require Logger

  @doc ~s"""
  Takes a list of triggers and returns its a list of those triggers that are
  triggered at the current time and the user should be notified about.
  """
  @spec run(list(), String.t() | nil) :: list()
  def run(user_triggers, type \\ nil)

  def run([], _), do: []

  def run(user_triggers, type) do
    Logger.info("Start evaluating #{length(user_triggers)} signals of type #{type}")

    user_triggers
    |> Sanbase.Parallel.map(
      &evaluate/1,
      ordered: false,
      max_concurrency: 8,
      timeout: 90_000,
      on_timeout: :kill_task
    )
    |> filter_triggered(type)
    |> populate_payload()
  end

  defp evaluate(%UserTrigger{trigger: trigger} = user_trigger) do
    %{cooldown: cd, last_triggered: lt} = trigger

    # Along with the trigger settings (the `cache_key`) take into account also
    # the last triggered datetime and cooldown. This is done because a signal
    # can only be fired if it did not fire in the past `cooldown` intereval of time
    evaluated_trigger =
      Cache.get_or_store(
        {Trigger.cache_key(trigger), {lt, cd}},
        fn -> Trigger.evaluate(trigger) end
      )

    # Take only `template_kv` and `triggered?` from the cache. Each `put` is done
    # by a separete `put_in` invocation
    user_trigger
    |> put_in(
      [Access.key!(:trigger), Access.key!(:settings), Access.key!(:template_kv)],
      evaluated_trigger.settings.template_kv
    )
    |> put_in(
      [Access.key!(:trigger), Access.key!(:settings), Access.key!(:triggered?)],
      evaluated_trigger.settings.triggered?
    )
  end

  defp filter_triggered(triggers, type) do
    triggers
    |> Enum.filter(fn
      %UserTrigger{trigger: trigger} ->
        Trigger.triggered?(trigger)

      {:exit, :timeout} ->
        Logger.info("A trigger of type #{type} has timed out and has been killed.")
        false

      _ ->
        false
    end)
  end

  defp populate_payload(triggers) do
    triggers
    |> Enum.map(fn %UserTrigger{} = user_trigger ->
      template_kv = user_trigger.trigger.settings.template_kv

      payload =
        Enum.into(template_kv, %{}, fn {identifier, {template, kv}} ->
          {identifier, Trigger.payload_to_string({template, kv})}
        end)

      user_trigger
      |> put_in(
        [Access.key!(:trigger), Access.key!(:settings), Access.key!(:payload)],
        payload
      )
    end)
  end
end
