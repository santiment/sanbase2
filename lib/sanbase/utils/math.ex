defmodule Sanbase.Math do
  require Integer

  @epsilon 1.0e-6

  @doc ~s"""
  Calculate the % change that occured between the first and the second arguments

    ## Examples

      iex> Sanbase.Math.percent_change(1.0, 2.0)
      100.0

      iex> Sanbase.Math.percent_change(1.0, 1.05)
      5.0

      iex> Sanbase.Math.percent_change(0, 2.0)
      0.0

      iex> Sanbase.Math.percent_change(2.0, 1.0)
      -50.0

      iex> Sanbase.Math.percent_change(2.0, 0.0)
      -100.0

      iex> Sanbase.Math.percent_change(2.0, -1)
      -150.0

      iex> Sanbase.Math.percent_change(10.0, 10.0)
      0.0
  """
  def percent_change(0, _current_daa), do: 0.0
  def percent_change(nil, _current_daa), do: 0.0

  def percent_change(previous, _current_daa)
      when is_number(previous) and previous <= @epsilon,
      do: 0

  def percent_change(previous, current) when is_number(previous) and is_number(current) do
    Float.round((current - previous) / previous * 100, 2)
  end

  @doc ~S"""
  Integer power function. Erlang's :math is using floating point numbers.
  Sometimes the result is needed as Integer and not as Float (ex. for using in Decimal.div/1)
  and it's inconvenient to polute the code with `round() |> trunc()`

  ## Examples

      iex> Sanbase.Math.ipow(2,2)
      4
      iex> Sanbase.Math.ipow(-2,2)
      4
      iex> Sanbase.Math.ipow(-2,3)
      -8
      iex> Sanbase.Math.ipow(1231232,0)
      1
      iex> Sanbase.Math.ipow(2,500)
      3273390607896141870013189696827599152216642046043064789483291368096133796404674554883270092325904157150886684127560071009217256545885393053328527589376
      iex> Sanbase.Math.ipow(10,18)
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

  @doc ~S"""
  Convert strings, floats, decimals or integers to integers

  ## Examples

      iex> Sanbase.Math.to_integer("2")
      2
      iex> Sanbase.Math.to_integer(2.3)
      2
      iex> Sanbase.Math.to_integer(2.5)
      3
      iex> Sanbase.Math.to_integer(2.8)
      3
      iex> Sanbase.Math.to_integer(2.0)
      2
      iex> Sanbase.Math.to_integer(Decimal.new(2))
      2
      iex> Sanbase.Math.to_integer(500)
      500
  """
  def to_integer(x) when is_integer(x), do: x

  def to_integer(f) when is_float(f) do
    f |> round() |> trunc()
  end

  def to_integer(%Decimal{} = d) do
    d |> Decimal.round() |> Decimal.to_integer()
  end

  def to_integer(str) when is_binary(str) do
    String.trim(str) |> String.to_integer()
  end

  @doc ~S"""
  Convert a string that potentially contains trailing non-digit symbols to an integer

  ## Examples

      iex> Sanbase.Math.str_to_integer_safe("2asd")
      2

      iex> Sanbase.Math.str_to_integer_safe("222")
      222
  """
  def str_to_integer_safe(str) do
    case Integer.parse(str) do
      {num, _rest} -> num
      :error -> nil
    end
  end

  @doc ~S"""
  Convert strings, floats, decimals or integers to floats

  ## Examples

      iex> Sanbase.Math.to_float("2")
      2.0
      iex> Sanbase.Math.to_float(2.3)
      2.3
      iex> Sanbase.Math.to_float(2.5)
      2.5
      iex> Sanbase.Math.to_float(2.8)
      2.8
      iex> Sanbase.Math.to_float(2.0)
      2.0
      iex> Sanbase.Math.to_float(Decimal.new(2))
      2.0
      iex> Sanbase.Math.to_float(500)
      500.0
  """
  def to_float(data, default_when_nil \\ nil)
  def to_float(nil, default_when_nil), do: default_when_nil
  def to_float(fl, _) when is_float(fl), do: fl
  def to_float(int, _) when is_integer(int), do: int * 1.0

  def to_float(%Decimal{} = d, _) do
    d |> Decimal.to_float()
  end

  def to_float(str, _) when is_binary(str) do
    {num, _} = str |> Float.parse()
    num
  end

  @doc ~s"""
  Find the min and max in a list in a single pass. The result is returned
  as a tuple `{min, max}` or `nil` if the list is empty

  ## Examples
      iex> Sanbase.Math.min_max([1,2,3,-1,2,1])
      {-1, 3}

      iex> Sanbase.Math.min_max([:a])
      {:a, :a}

      iex> Sanbase.Math.min_max([])
      nil
  """
  def min_max([]), do: nil

  def min_max([h | rest]) do
    rest
    |> Enum.reduce({h, h}, fn
      elem, {min, max} when elem < min -> {elem, max}
      elem, {min, max} when elem > max -> {min, elem}
      _, acc -> acc
    end)
  end

  def average(list, opts \\ [])
  def average([], _), do: 0

  def average(values, opts),
    do: Float.round(Enum.sum(values) / length(values), Keyword.get(opts, :precision, 2))

  def median([]), do: nil

  def median(list) when is_list(list) do
    list = Enum.sort(list)

    midpoint =
      (length(list) / 2)
      |> Float.floor()
      |> round

    {l1, l2} = list |> Enum.split(midpoint)

    # l2 is the same length as l1 or 1 element bigger as the midpoint is floored
    case length(l2) > length(l1) do
      true ->
        [med | _] = l2
        med

      false ->
        [m1 | _] = l2
        m2 = List.last(l1)
        average([m1, m2])
    end
  end

  def simple_moving_average(values, period) do
    values
    |> Enum.chunk_every(period, 1, :discard)
    |> Enum.map(&average/1)
  end

  def simple_moving_average(list, period, opts) do
    value_key = Keyword.fetch!(opts, :value_key)

    result =
      list
      |> Enum.chunk_every(period, 1, :discard)
      |> Enum.map(fn elems ->
        datetime = Map.get(List.last(elems), :datetime)
        values = Enum.map(elems, & &1[value_key])

        %{
          value_key => average(values),
          :datetime => datetime
        }
      end)

    {:ok, result}
  end
end
