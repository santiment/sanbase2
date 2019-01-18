defmodule SanbaseWeb.Graphql.ConCacheProvider do
  @behaviour SanbaseWeb.Graphql.CacheProvider

  def get(cache, key) do
    ConCache.get(cache, key)
  end

  def store(cache, key, value) do
    ConCache.put(cache, key, value) == :ok
  end

  def get_or_store(cache, key, func, middleware_func) do
    {result, error_if_any} =
      if (value = ConCache.get(cache, key)) != nil do
        {value, nil}
      else
        ConCache.isolated(cache, key, fn ->
          if (value = ConCache.get(cache, key)) != nil do
            {value, nil}
          else
            case func.() do
              {:error, _} = error ->
                {nil, error}

              {:ok, _value} = tuple ->
                ConCache.put(cache, key, tuple)
                {tuple, nil}

              {:middleware, _, _} = tuple ->
                # Decides on its behalf whether or not to put the value in the cache
                {middleware_func.(cache, cache, tuple), nil}
            end
          end
        end)
      end

    if error_if_any != nil do
      error_if_any
    else
      result
    end
  end
end
