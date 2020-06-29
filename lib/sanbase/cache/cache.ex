defmodule Sanbase.Cache do
  @behaviour Sanbase.Cache.Behaviour
  @cache_name :sanbase_cache
  @max_cache_ttl 86_400

  def hash(data) do
    :crypto.hash(:sha256, data |> :erlang.term_to_binary())
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

  @impl Sanbase.Cache.Behaviour
  def get_or_store(cache \\ @cache_name, key, func)

  def get_or_store(cache, key, func) do
    true_key = true_key(key)

    {result, error_if_any} =
      case ConCache.get(cache, true_key) do
        {:stored, value} ->
          {value, nil}

        _ ->
          ConCache.isolated(cache, true_key, fn ->
            case ConCache.get(cache, true_key) do
              {:stored, value} ->
                {value, nil}

              _ ->
                case func.() do
                  {:error, _} = error ->
                    {nil, error}

                  {:nocache, {:ok, _result} = value} ->
                    {value, nil}

                  value ->
                    cache_item(cache, key, {:stored, value})
                    {value, nil}
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

  defp cache_item(cache, {key, ttl}, value) when is_integer(ttl) and ttl <= @max_cache_ttl do
    ConCache.put(cache, key, %ConCache.Item{value: value, ttl: :timer.seconds(ttl)})
  end

  defp cache_item(cache, key, value) do
    ConCache.put(cache, key, value)
  end

  defp true_key({key, ttl}) when is_integer(ttl) and ttl <= @max_cache_ttl, do: key
  defp true_key(key), do: key
end
