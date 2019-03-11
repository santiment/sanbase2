defmodule Sanbase.Signals.Evaluator.Cache do
  @moduledoc ~s"""
  Cache that is used during custom user signals evaluation. A subset of the
  signal's settings that uniquely determine the outcome are usead to generate a sha256
  hash so 2 signals with the same settings are going to be executed only once.

  The TTL of the cache is small (3 minutes) with 1 minute checks so it will expire
  before the signals are scheduled again (5 minutes).
  """

  require Logger
  @cache_name :signals_evaluator_cache

  def get_or_store(key, func) when is_function(func, 0) do
    {result, error_if_any} =
      if (result = ConCache.get(@cache_name, key)) != nil do
        {:stored, value} = result
        {value, nil}
      else
        ConCache.isolated(@cache_name, key, fn ->
          if (result = ConCache.get(@cache_name, key)) != nil do
            {:stored, value} = result
            {value, nil}
          else
            case func.() do
              {:error, _} = error ->
                {nil, error}

              value ->
                ConCache.put(@cache_name, key, {:stored, value})
                {value, nil}
            end
          end
        end)
      end

    if error_if_any != nil do
      Logger.info("Error while evaluating a signal: #{inspect(error_if_any)}")
      error_if_any
    else
      result
    end
  end

  def clear() do
    @cache_name
    |> ConCache.ets()
    |> :ets.tab2list()
    |> Enum.each(fn {key, _} -> ConCache.delete(@cache_name, key) end)
  end
end
