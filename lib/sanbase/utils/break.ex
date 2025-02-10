defmodule Sanbase.Break do
  @moduledoc false
  defmodule CompileError do
    @moduledoc false
    defexception [:message]
  end

  defmacro break(value) do
    quote do
      raise(CompileError, unquote(value))
    end
  end

  def if_kw_invalid?(keyword_list, opts) do
    valid_keys = Keyword.fetch!(opts, :valid_keys)

    for {k, _} <- keyword_list,
        k not in valid_keys,
        do: raise("Unknown key #{inspect(k)} in #{inspect(keyword_list)}")
  end
end
