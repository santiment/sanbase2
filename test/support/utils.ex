defmodule Sanbase.TestUtils do
  @doc ~s"""
    Return `true` if the distance between the two numbers `a` and `b` is less than
    or equal to `distance`. Return `false` otherwise.
  """
  @spec close_to(number(), number(), number()) :: boolean()
  def close_to(a, b, distance) when is_number(a) and is_number(b) and is_number(distance) do
    if abs(a - b) <= distance do
      true
    else
      false
    end
  end

  @doc ~s"""
    Return `true` if two dates `a` and `b` are closer than `distance` measured in `granularity`.
    Return `false` otherwise.
  """
  @spec date_close_to(%DateTime{}, %DateTime{}, number(), atom()) :: boolean()
  def date_close_to(a, b, distance, granularity \\ :seconds) do
    diff = abs(Timex.diff(a, b, granularity))

    if diff <= distance do
      true
    else
      false
    end
  end
end
