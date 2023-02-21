defmodule Sanbase.Math do
  require Integer

  @epsilon 1.0e-6

  defguard float_eq?(l, r) when abs(l - r) <= @epsilon

  def round_float(f) when is_float(f) and (f >= 1 or f <= -1), do: Float.round(f, 2)
  def round_float(f) when is_float(f) and f >= 0 and f <= @epsilon, do: 0.0
  def round_float(f) when is_float(f) and f < 0 and f >= -@epsilon, do: 0.0
  def round_float(f) when is_float(f), do: Float.round(f, 6)
  def round_float(i) when is_integer(i), do: round(i * 1.0)

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
  def percent_change(0, _current), do: 0.0
  def percent_change(nil, _current), do: 0.0
  def percent_change(_previous, nil), do: 0.0

  def percent_change(previous, _current)
      when is_number(previous) and previous <= @epsilon,
      do: 0.0

  def percent_change(previous, current) when is_number(previous) and is_number(current) do
    ((current / previous - 1) * 100)
    |> Float.round(2)
  end

  @spec percent_of(number(), number(), Keyword.t()) :: number() | nil
  def percent_of(part, whole, opts \\ [])

  def percent_of(part, whole, opts)
      when is_number(part) and is_number(whole) and part >= 0 and whole > 0 and whole >= part do
    result =
      case Keyword.get(opts, :type, :between_0_and_100) do
        :between_0_and_1 ->
          part / whole

        :between_0_and_100 ->
          part / whole * 100
      end

    precision = Keyword.get(opts, :precision, 15)
    Float.floor(result, precision)
  end

  def percent_of(_, _, _), do: nil

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
    # Since Elixir 1.12.0 Integer.pow/2 is available
    Integer.pow(base, exp)
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
  def to_integer(x, default_when_nil \\ nil)

  def to_integer(nil, default_when_nil), do: default_when_nil
  def to_integer(x, _) when is_integer(x), do: x
  def to_integer(f, _) when is_float(f), do: f |> round() |> trunc()
  def to_integer(%Decimal{} = d, _), do: d |> Decimal.round() |> Decimal.to_integer()

  def to_integer(str, _) when is_binary(str) do
    case String.trim(str) |> Integer.parse() do
      {integer, _} ->
        integer

      :error ->
        {:error, "Cannot parse an integer from #{str}"}
    end
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

  @doc ~s"""
  Compute the mean of the numbers in the list. The float precision is 2 by default.
  Provide :precision option to change that.

  ## Examples
    iex> Sanbase.Math.mean([1,2,3,4,5,6,7,8,9,10])
    5.5

    iex> Sanbase.Math.mean([5])
    5.0

    iex> Sanbase.Math.mean([])
    0.0
  """
  def mean(list, opts \\ [])
  def mean([], _), do: 0.0

  def mean(values, opts) do
    mean = Enum.sum(values) / length(values)

    # In case the precision is not provided, round the according
    # to some predfined rules (use more precision for smaller numbers)
    case Keyword.get(opts, :precision) do
      nil -> mean |> round_float()
      precision -> Float.round(mean, precision)
    end
  end

  @doc ~s"""
  Compute the median of the numbers in the list

  ## Examples
    iex> Sanbase.Math.median([1,2,3,4,5,6,7,8,9,10])
    5.5

    iex> Sanbase.Math.median([1,2,3,4,5,6,7,8,9])
    5

    iex> Sanbase.Math.median([5, 1, 12])
    5

    iex> Sanbase.Math.median([])
    nil
  """
  def median([]), do: nil

  def median(list) when is_list(list) do
    list = Enum.sort(list)

    midpoint =
      (length(list) / 2)
      |> Float.floor()
      |> trunc()

    {l1, l2} = list |> Enum.split(midpoint)

    # l2 is the same length as l1 or 1 element bigger as the midpoint is floored
    case length(l2) > length(l1) do
      true ->
        [med | _] = l2
        med

      false ->
        [m1 | _] = l2
        m2 = List.last(l1)
        mean([m1, m2])
    end
  end

  @doc ~s"""
  Compute the population variance of the numbers in the list. The list is expected
  to contain the whole dataset, not just a sample from it.

  The variance tells you the degree of spread in the data. It judges how far
  from the mean is each value, weighted by the distance.

  ## Examples
    iex> Sanbase.Math.variance([1,2,3,4,5,6,7,8,9,10])
    8.25

    iex> Sanbase.Math.variance([-1,-2,-3,4,5,6,7,8,9])
    18.22

    iex> Sanbase.Math.variance([5, 5, 5])
    0.0

    iex> Sanbase.Math.variance([])
    nil
  """
  def variance(list, opts \\ [])
  def variance([], _opts), do: nil

  def variance(list, opts) when is_list(list) do
    mean = mean(list, opts)

    list
    |> Enum.map(fn val -> (mean - val) * (mean - val) end)
    |> mean(opts)
  end

  @doc ~s"""
  Compute the standard deviation of the numbers in the list.
  The standard deviation is the square root of the variance. It is used often
  as it is in the same unit as the raw data.

  ## Examples
    iex> Sanbase.Math.stdev([1,2,3,4,5,6,7,8,9,10])
    2.87

    iex> Sanbase.Math.stdev([-1,-2,-3,4,5,6,7,8,9])
    4.26

    iex> Sanbase.Math.stdev([5, 5, 5])
    0.0

    iex> Sanbase.Math.stdev([])
    nil
  """
  def stdev(list, opts \\ [])
  def stdev([], _opts), do: nil

  def stdev(list, opts) when is_list(list) do
    list
    |> variance()
    |> :math.sqrt()
    |> Float.floor(Keyword.get(opts, :precision, 2))
  end

  @doc ~s"""
  Compute the Z score over the list of numbers. Returns error if the
  numbers have standard deviation of 0 as Z score is computed only on
  data with a probablistic distribution (not all numbers are equal)

  ## Examples
    iex> Sanbase.Math.zscore([1,2,3,4,5,6,7,8,9,10])
    [-1.57, -1.22, -0.88, -0.53, -0.18, 0.17, 0.52, 0.87, 1.21, 1.56]

    iex> Sanbase.Math.zscore([-1,-2,-3,4,5,6,7,8,9])
    [-1.1, -1.34, -1.57, 0.07, 0.31, 0.54, 0.78, 1.01, 1.25]

    iex> Sanbase.Math.zscore([5.0e10, 5, 5])
    [1.41, -0.71, -0.71]

    iex> Sanbase.Math.zscore([5, 5, 5])
    {:error, "Cannot compute zscore on constant timeseries."}

    iex> Sanbase.Math.zscore([])
    nil
  """
  def zscore(list, opts \\ [])
  def zscore([], _opts), do: nil

  def zscore(list, opts) when is_list(list) do
    with mean <- mean(list),
         stdev when stdev != nil and not float_eq?(stdev, 0.0) <- stdev(list) do
      precision = Keyword.get(opts, :precision, 2)
      Enum.map(list, fn val -> ((val - mean) / stdev) |> Float.floor(precision) end)
    else
      _ -> {:error, "Cannot compute zscore on constant timeseries."}
    end
  end

  def simple_moving_average(values, period) do
    values
    |> Enum.chunk_every(period, 1, :discard)
    |> Enum.map(&mean/1)
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
          value_key => mean(values),
          :datetime => datetime
        }
      end)

    {:ok, result}
  end
end
