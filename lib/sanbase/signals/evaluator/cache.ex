defmodule Sanbase.Signal.Evaluator.Cache do
  @cache_name :signals_evaluator_cache

  def get_or_store(cache_key, fun) when is_function(fun, 0) do
    ConCache.get_or_store(@cache_name, cache_key, fun)
  end
end
