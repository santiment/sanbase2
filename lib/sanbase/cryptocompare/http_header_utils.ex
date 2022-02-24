defmodule Sanbase.Cryptocompare.HTTPHeaderUtils do
  defmodule Parser do
    import NimbleParsec

    pair =
      ignore(string(" "))
      |> integer(min: 1, max: 30)
      |> ignore(string(";window="))
      |> integer(min: 1, max: 30)
      |> optional(ignore(string(",")))

    leading_integer =
      ignore(integer(min: 1, max: 30))
      |> ignore(string(","))

    defparsec(:list_of_values, leading_integer |> repeat(pair))
  end

  @doc ~s"""
  Parse the X-RateLimit-Reset-All header value returned by cryptocompare.
  The list of values is parsed into a list of maps, each of which has the time
  period and the reset after in seconds.

  ## Examples
    iex> Sanbase.Cryptocompare.HTTPHeaderUtils.parse_value_list("1220397, 1;window=1, 33;window=60, 2673;window=3600, 38673;window=86400, 1220397;window=2592000")
    [
      %{value: 1, time_period: 1},
      %{value: 33, time_period: 60},
      %{value: 2673, time_period: 3600},
      %{value: 38673, time_period: 86400},
      %{value: 1220397, time_period: 2592000}
    ]

    iex> Sanbase.Cryptocompare.HTTPHeaderUtils.parse_value_list("1220397, 9500;window=1, 9500;window=60, 9500;window=3600, 38673;window=86400, 1220397;window=2592000")
    [
      %{value: 9500, time_period: 1},
      %{value: 9500, time_period: 60},
      %{value: 9500, time_period: 3600},
      %{value: 38673, time_period: 86400},
      %{value: 1220397, time_period: 2592000}
    ]
  """
  def parse_value_list(header_value) do
    case Parser.list_of_values(header_value) do
      {:ok, list, "", %{}, _, _} ->
        list
        |> Enum.chunk_every(2)
        |> Enum.map(fn [reset_after, time_period] ->
          %{
            time_period: time_period,
            value: reset_after
          }
        end)

      _ ->
        {:error, :parse_error}
    end
  end
end
