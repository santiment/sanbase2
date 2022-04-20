defmodule Sanbase.WatchlistFunction.Query do
  alias Sanbase.WatchlistFunction
  alias Sanbase.UserList

  defmacro function_name_any(names) do
    quote do
      fragment(
        """
        function->>'name' = ANY(?)
        """,
        ^unquote(names)
      )
    end
  end
end
