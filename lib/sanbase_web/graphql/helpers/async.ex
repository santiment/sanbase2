defmodule SanbaseWeb.Graphql.Helpers.Async do
  @doc ~s"""
  Macro to be used instead of `Absinthe.Resolution.Helpers.async`.
  This macro falls back to the Absinthe's async in `:dev` and `:prod` but in
  `:test` env just executes the function as if no `async` has been used
  """

  # Must exceed the 85s ClickHouse budget so a slow query surfaces
  # {:error, timeout} instead of a Task exit → 500. See docs/timeouts.md.
  @async_timeout_ms 105_000

  defmacro async(func, opts \\ []) do
    quote bind_quoted: [func: func, opts: opts, default_timeout_ms: @async_timeout_ms] do
      if Sanbase.Utils.Config.module_get(Sanbase, :env) == :test do
        func.()
      else
        Absinthe.Resolution.Helpers.async(
          func,
          Keyword.put_new(opts, :timeout, default_timeout_ms)
        )
      end
    end
  end
end
