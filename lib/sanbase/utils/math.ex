defmodule Sanbase.Utils.Math do
  require Integer

  @doc ~S"""
  Integer power function. Erlang's :math is using floating point numbers.
  Sometimes the result is needed as Integer and not as Float (ex. for using in Decimal.div/1)
  and it's inconvenient to polute the code with `round() |> trunc()`

  ## Examples

      iex> Sanbase.Utils.Math.ipow(2,2)
      4
      iex> Sanbase.Utils.Math.ipow(-2,2)
      4
      iex> Sanbase.Utils.Math.ipow(-2,3)
      -8
      iex> Sanbase.Utils.Math.ipow(1231232,0)
      1
      iex> Sanbase.Utils.Math.ipow(2,500)
      3273390607896141870013189696827599152216642046043064789483291368096133796404674554883270092325904157150886684127560071009217256545885393053328527589376
      iex> Sanbase.Utils.Math.ipow(10,18)
      1_000_000_000_000_000_000

  """
  def ipow(base, exp) when is_integer(base) and is_integer(exp) and exp >= 0 do
    do_ipow(base, exp)
  end

  defp do_ipow(_, 0), do: 1

  defp do_ipow(x, 1), do: x

  defp do_ipow(x, n) when Integer.is_odd(n) do
    x * ipow(x, n - 1)
  end

  defp do_ipow(x, n) do
    result = do_ipow(x, div(n, 2))
    result * result
  end

  def to_integer(x) when is_integer(x), do: x

  def to_integer(f) when is_float(f) do
    f |> round() |> trunc()
  end

  def to_integer(%Decimal{} = d) do
    d |> Decimal.round() |> Decimal.round()
  end

  def to_integer(str) when is_binary(str) do
    String.to_integer(str)
  end

  def to_integer_safe(str) do
    case Integer.parse(str) do
      {num, _rest} -> num
      :error -> nil
    end
  end
end
