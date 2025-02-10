defmodule Sanbase.Alert.Utils do
  @moduledoc false
  alias Sanbase.Math

  @doc ~s"""
  Round the price to 6 digits if it's between 0 and 1.
  Round the price to 2 digits if it's above 1

    ## Examples

      iex> Sanbase.Alert.Utils.round_price(0.1023812093812312)
      0.102381

      iex> Sanbase.Alert.Utils.round_price(0.5)
      0.5

      iex> Sanbase.Alert.Utils.round_price(0.50000)
      0.5

      iex> Sanbase.Alert.Utils.round_price(5.012412412)
      5.01

      iex> Sanbase.Alert.Utils.round_price(5)
      5.0
  """
  def round_price(price) when is_number(price) and price > 0 and price < 1 do
    price |> Math.to_float() |> Float.round(6)
  end

  def round_price(price) when is_number(price) and price >= 1 do
    price |> Math.to_float() |> Float.round(2)
  end

  @doc ~s"""
  Construct a unique key by a given list of terms

    ## Examples

      iex> Sanbase.Alert.Utils.construct_cache_key([1,2,3]) != Sanbase.Alert.Utils.construct_cache_key([2,1,3])
      true

      iex> Sanbase.Alert.Utils.construct_cache_key([1,2,3]) == Sanbase.Alert.Utils.construct_cache_key([1,2,3])
      true

      iex> Sanbase.Alert.Utils.construct_cache_key([1,2,3]) |> is_binary()
      true
  """
  @spec construct_cache_key(list(any)) :: String.t()
  def construct_cache_key(keys) when is_list(keys) do
    data = Jason.encode!(keys)

    :sha256
    |> :crypto.hash(data)
    |> Base.encode16()
    |> binary_part(0, 32)
  end
end
