defmodule Sanbase.Cache.RehydratingCache.Store do
  def name(name), do: :"__rehydrating_cache_store_#{name}__"

  def put(store, key, data, ttl) when is_integer(ttl) and ttl > 0 do
    Sanbase.Cache.store(store, {key, ttl}, data)
  end

  def get(store, key) do
    Sanbase.Cache.get(store, key)
  end
end
