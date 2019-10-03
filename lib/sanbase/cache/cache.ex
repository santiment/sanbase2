defmodule Sanbase.Cache do
  @behaviour Sanbase.Cache.Behaviour
  @cache_name :sanbase_cache
  @max_cache_ttl 300
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
    case ConCache.get(cache, key) do
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

  @impl Sanbase.Cache.Behaviour
  def get_or_store(cache \\ @cache_name, key, func)

  def get_or_store(cache, key, func) do
    ConCache.fetch_or_store(cache, key, func)
  end

  defp cache_item(cache, {_, ttl} = key, value) when is_integer(ttl) and ttl <= @max_cache_ttl do
    ConCache.put(cache, key, %ConCache.Item{value: value, ttl: :timer.seconds(ttl)})
  end

  defp cache_item(cache, key, value) do
    ConCache.put(cache, key, value)
  end
end
