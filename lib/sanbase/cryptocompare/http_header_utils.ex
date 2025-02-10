defmodule Sanbase.Cryptocompare.HTTPHeaderUtils do
  @moduledoc false
  require Logger

  defmodule Parser do
    @moduledoc ~s"""
    Parse for the X-RateLimit-Remaining-All and X-RateLimit-Reset-All headers
    coming from Cryptocompare.

    Example value: "1220397, 1;window=1, 33;window=60, 2673;window=3600, 38673;window=86400, 1220397;window=2592000"
    """
    import NimbleParsec

    pair =
      " "
      |> string()
      |> ignore()
      |> integer(min: 1, max: 30)
      |> ignore(string(";window="))
      |> integer(min: 1, max: 30)
      |> optional(ignore(string(",")))

    leading_integer =
      [min: 1, max: 30]
      |> integer()
      |> ignore()
      |> ignore(string(","))

    defparsec(:list_of_values, repeat(leading_integer, pair))
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

  def get_biggest_ratelimited_window(resp) do
    resp
    |> get_header("X-RateLimit-Reset-All")
    |> elem(1)
    |> parse_value_list()
    |> Enum.max_by(& &1.value)
    |> Map.get(:value)
  end

  def rate_limited?(resp) do
    # If any of the rate limit periods has 0 remaining requests
    # it means that the rate limit is reached
    zero_remainings =
      resp
      |> get_header("X-RateLimit-Remaining-All")
      |> elem(1)
      |> parse_value_list()
      |> Enum.filter(&(&1.value == 0))

    case zero_remainings do
      [] ->
        false

      list ->
        {:error_limited, Enum.max_by(list, & &1.time_period)}
    end
  end

  def get_header(%HTTPoison.Response{} = resp, header) do
    Enum.find(resp.headers, &match?({^header, _}, &1))
  end
end
