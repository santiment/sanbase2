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
      max_concurrency: 100,
      timeout: 30_000
    )
    |> Enum.filter(&triggered?/1)
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

    # Take only `payload` and `triggered?` from the cache
    %UserTrigger{
      user_trigger
      | trigger: %{
          trigger
          | settings: %{
              trigger.settings
              | payload: evaluated_trigger.settings.payload,
                triggered?: evaluated_trigger.settings.triggered?
            }
        }
    }
  end

  defp triggered?(%UserTrigger{trigger: trigger}) do
    Trigger.triggered?(trigger)
  end
end
