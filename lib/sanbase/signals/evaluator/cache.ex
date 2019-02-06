defmodule Sanbase.Signals.Evaluator.Cache do
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
