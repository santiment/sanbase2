defmodule Sanbase.Cryptocompare.HTTPHeaderUtils do
  import NimbleParsec

  pair =
    ignore(string(" "))
    |> integer(min: 1, max: 20)
    |> ignore(string(";window="))
    |> integer(min: 1, max: 20)
    |> ignore(string(","))

  leading_integer =
    ignore(integer(min: 1, max: 20))
    |> ignore(string(","))

  defparsec(:reset_all, leading_integer |> repeat(pair))
end

value =
  "1220397, 1;window=1, 33;window=60, 2673;window=3600, 38673;window=86400, 1220397;window=2592000"
