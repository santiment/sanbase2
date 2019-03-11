defmodule Sanbase.Model.ProjectQuery do
  defmacro coalesce(left, right) do
    quote do
      fragment("COALESCE(?, ?)", unquote(left), unquote(right))
    end
  end

  defmacro volume_above(_, nil) do
    quote do
      fragment("1 = 1")
    end
  end

  defmacro volume_above(volume, min_volume) when is_number(min_volume) and min_volume >= 0 do
    quote do
      fragment(
        "? > ?",
        ^unquote(volume),
        ^unquote(min_volume)
      )
    end
  end
end
