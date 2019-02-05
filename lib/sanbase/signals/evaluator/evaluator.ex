defmodule Sanbase.Signals.Evaluator do
  @moduledoc ~s"""
  A module that takes a list of triggers and returns the ones that must be triggered
  """

  alias Sanbase.Signals.Evaluator.Cache
  alias Sanbase.Signals.{UserTrigger, Trigger}

  @doc ~s"""
  Takes a list of triggers and returns its subset that evaluate to true at the given moment.
  """
  @spec run(list()) :: list()
  def run(user_triggers) do
    user_triggers
    |> remove_triggers_on_cooldown()
    |> Sanbase.Parallel.pmap_concurrent(
      &evaluate/1,
      ordered: false,
      max_concurrency: 50,
      timeout: 30_000
    )
    |> Enum.filter(&triggered?/1)
  end

  defp remove_triggers_on_cooldown(triggers) do
    triggers
    |> Enum.reject(fn %{trigger: trigger} ->
      Trigger.has_cooldown?(trigger)
    end)
  end

  defp evaluate(%UserTrigger{trigger: trigger} = user_trigger) do
    Cache.get_or_store(
      Trigger.cache_key(trigger),
      fn -> %UserTrigger{user_trigger | trigger: Trigger.evaluate(trigger)} end
    )
  end

  defp triggered?(%UserTrigger{trigger: trigger}) do
    Trigger.triggered?(trigger)
  end
end
