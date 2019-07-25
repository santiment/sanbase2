defmodule Sanbase.Break do
  defmodule CompileError do
    defexception [:message]
  end

  defmacro break(value) do
    quote do
      raise(CompileError, unquote(value))
    end
  end
end
