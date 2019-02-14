defmodule Sanbase.Signals.Evaluator.Cache do
  @moduledoc ~s"""
  Cache that is used during custom user signals evaluation. A subset of the
  signal's settings that uniquely determine the outcome are usead to generate a sha256
  hash so 2 signals with the same settings are going to be executed only once.

  The TTL of the cache is small (3 minutes) with 1 minute checks so it will expire
  before the signals are scheduled again (5 minutes).
  """
  @cache_name :signals_evaluator_cache

  def get_or_store(cache_key, fun) when is_function(fun, 0) do
    ConCache.get_or_store(@cache_name, cache_key, fun)
  end

  def clear() do
    @cache_name
    |> ConCache.ets()
    |> :ets.tab2list()
    |> Enum.each(fn {key, _} -> ConCache.delete(@cache_name, key) end)
  end
end
