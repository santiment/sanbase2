defmodule SanbaseWeb.Graphql.Helpers.Async do
  require Absinthe.Resolution.Helpers

  @doc ~s"""
  Macro to be used instead of `Absinthe.Resolution.Helpers.async`.
  This macro falls back to the Absinthe's async in `:dev` and `:prod` but in
  `:test` env just executes the function as if no `async` has been used
  """
  defmacro async(func) do
    quote bind_quoted: [func: func] do
      if Mix.env() == :test do
        func.()
      else
        Absinthe.Resolution.Helpers.async(func)
      end
    end
  end
end
