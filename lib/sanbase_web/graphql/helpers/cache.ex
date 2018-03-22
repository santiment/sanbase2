defmodule SanbaseWeb.Graphql.Helpers.Cache do
  @ttl 5 * 60 * 1000

  def resolver(resolver_fn, name) do
    fn parent, args, resolution ->
      {_, value} =
        Cachex.fetch(
          :graphql_cache,
          cache_key(name, args),
          fn ->
            {:commit, resolver_fn.(parent, args, resolution)}
          end,
          ttl: @ttl
        )

      value
    end
  end

  def func(cached_func, name, args \\ %{}) do
    fn ->
      {_, value} =
        Cachex.fetch(
          :graphql_cache,
          cache_key(name, args),
          fn ->
            {:commit, cached_func.()}
          end,
          ttl: @ttl
        )

      value
    end
  end

  defp cache_key(name, args) do
    args_hash =
      args
      |> convert_values
      |> Poison.encode!()
      |> sha256

    {name, args_hash}
  end

  defp convert_values(args) do
    args
    |> Enum.map(fn
      {k, %DateTime{} = v} ->
        {k, div(DateTime.to_unix(v, :millisecond), @ttl)}

      pair ->
        pair
    end)
    |> Map.new()
  end

  defp sha256(data) do
    :crypto.hash(:sha256, data)
    |> Base.encode16()
  end
end
