defmodule Sanbase.Signals.Evaluator do
  @module ~s"""
  A module that takes a list of triggers and returns the ones that must be triggered
  """

  alias Sanbase.Repo
  alias Sanbase.Signal.Evaluator.Cache

  @doc ~s"""
  Takes a list of triggers and returns its subset that evaluate to true at the given moment.
  """
  @spec run(list()) :: list()
  def run(triggers) do
    triggers
    |> remove_triggers_on_cooldown()
    |> Sanbase.Parallel.pfilter_concurrent(&filter_triggered/1,
      ordered: false,
      max_concurrency: 50,
      timeout: 30_000
    )
    |> mark_as_triggered()
  end

  defp remove_triggers_on_cooldown(triggers) do
    triggers |> Enum.reject(&has_cooldown?/1)
  end

  defp mark_as_triggered(triggers) do
    triggers
    |> Repo.update_all(set: [last_triggered: Timex.now()])
  end

  defp has_cooldown?(%{last_triggered: nil}), do: false
  defp has_cooldown?(%{cooldown: nil}), do: false

  defp has_cooldown?(%{cooldown: cd, last_triggered: %DateTime{} = lt}) do
    Timex.compare(
      Timex.shift(lt, minutes: cd),
      Timex.now()
    ) == 1
  end

  defp filter_triggered({_type, []}), do: []

  defp filter_triggered({_type, triggers}) do
    [%trigger_module{} | _] = triggers

    triggers
    |> Enum.filter(fn trigger ->
      Cache.get_or_store(
        trigger_module.cache_key(trigger),
        fn -> trigger_module.triggered?(trigger) end
      )
    end)
  end
end
