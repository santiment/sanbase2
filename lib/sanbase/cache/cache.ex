defmodule Sanbase.Cache do
  @behaviour Sanbase.Cache.Behaviour
  @cache_name :sanbase_cache
  @max_cache_ttl 86_400

  @compile {:inline, get_or_store_isolated: 4}

  def child_spec(opts) do
    Supervisor.child_spec(
      {ConCache,
       [
         name: Keyword.fetch!(opts, :name),
         ttl_check_interval: Keyword.get(opts, :ttl_check_interval, :timer.seconds(5)),
         global_ttl: Keyword.get(opts, :global_ttl, :timer.minutes(5)),
         acquire_lock_timeout: Keyword.get(opts, :aquire_lock_timeout, 30_000)
       ]},
      id: Keyword.fetch!(opts, :id)
    )
  end

  def hash(data) do
    :crypto.hash(:sha256, :erlang.term_to_binary(data))
    |> Base.encode64()
  end

  def name, do: @cache_name

  @impl Sanbase.Cache.Behaviour
  def size(cache \\ @cache_name, size_type)

  def size(cache, :megabytes) do
    bytes_size = :ets.info(ConCache.ets(cache), :memory) * :erlang.system_info(:wordsize)
    (bytes_size / (1024 * 1024)) |> Float.round(2)
  end

  @impl Sanbase.Cache.Behaviour
  def clear_all(cache \\ @cache_name)

  def clear_all(cache) do
    cache
    |> ConCache.ets()
    |> :ets.tab2list()
    |> Enum.each(fn {key, _} -> ConCache.delete(cache, key) end)
  end

  @impl Sanbase.Cache.Behaviour
  def get(cache \\ @cache_name, key)

  def get(cache, key) do
    case ConCache.get(cache, true_key(key)) do
      {:stored, value} -> value
      nil -> nil
    end
  end

  @impl Sanbase.Cache.Behaviour
  def store(cache \\ @cache_name, key, value)

  def store(cache, key, value) do
    case value do
      {:error, _} ->
        :ok

      value ->
        cache_item(cache, key, {:stored, value})
    end
  end

  @doc ~s"""
  Get the value from the cache, or, if it does not exist there, compute it after
  locking the key. This locking guarantees that if 100 concurrent processes try
  to get this value, only one of them will do the actual computation and all other
  will wait. This greatly reduces the DB load that will otherwise occur.
  """
  @impl Sanbase.Cache.Behaviour
  def get_or_store(cache \\ @cache_name, key, func)

  def get_or_store(_cache, :nocache, func), do: func.()
  def get_or_store(_cache, {:nocache, _}, func), do: func.()

  def get_or_store(cache, key, func) do
    true_key = true_key(key)

    case ConCache.get(cache, true_key) do
      {:stored, value} ->
        value

      _ ->
        get_or_store_isolated(cache, key, true_key, func)
    end
  end

  defp get_or_store_isolated(cache, key, true_key, func) do
    # This function is to be executed inside ConCache.isolated/3 call.
    # This isolated call locks the access for that key before doing anything else
    # Doing this ensures that the case where another process modified the key
    # before in the time between the previous check and the locking.
    fun = fn ->
      case ConCache.get(cache, true_key) do
        {:stored, value} ->
          value

        _ ->
          execute_and_maybe_cache_function(cache, key, func)
      end
    end

    ConCache.isolated(cache, true_key, fun)
  end

  defp execute_and_maybe_cache_function(cache, key, func) do
    # Execute the function and if it returns :ok tuple cache it
    # Errors are not cached. Also, caching can be manually disabled by
    # wrapping the result in a :nocache tuple
    case func.() do
      {:error, _} = error ->
        error

      {:nocache, {:ok, _result} = value} ->
        value

      value ->
        cache_item(cache, key, {:stored, value})
        value
    end
  end

  defp cache_item(cache, {key, ttl}, value) when is_integer(ttl) and ttl <= @max_cache_ttl do
    ConCache.put(cache, key, %ConCache.Item{value: value, ttl: :timer.seconds(ttl)})
  end

  defp cache_item(cache, key, value) do
    ConCache.put(cache, key, value)
  end

  defp true_key({key, ttl}) when is_integer(ttl) and ttl <= @max_cache_ttl, do: key
  defp true_key(key), do: key
end
