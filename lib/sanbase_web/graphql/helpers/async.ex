defmodule SanbaseWeb.Graphql.Helpers.Async do
  @doc ~s"""
  Macro to be used instead of `Absinthe.Resolution.Helpers.async`.
  This macro falls back to the Absinthe's async in `:dev` and `:prod` but in
  `:test` env just executes the function as if no `async` has been used
  """

  # Task.await budget for async resolvers. Must exceed the ClickHouse query
  # timeout (100s, config.exs) so a slow query surfaces its {:error, timeout}
  # message instead of the Task exit crashing the request into a 500.
  # See docs/timeouts.md for the full chain.
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
