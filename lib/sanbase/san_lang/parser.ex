defmodule Sanbase.SanLang.Parser do
  import NimbleParsec

  symbol =
    ascii_string([?a..?z, ?A..?Z, ?_], min: 1)
    |> concat(ascii_string([?a..?z, ?A..?Z, ?_, ?0..?9], max: 100))
    |> reduce({Enum, :join, [""]})
    |> unwrap_and_tag(:symbol)

  env_var =
    string("@")
    |> concat(ascii_string([?a..?z, ?A..?Z, ?_, ?0..?9], max: 100))
    |> reduce({Enum, :join, [""]})
    |> unwrap_and_tag(:env_var)

  access_operator =
    ignore(string(~S|["|))
    |> concat(symbol)
    |> ignore(string(~S|"]|))
    |> unwrap_and_tag(:access_operator)

  whitespace = string(" ") |> ignore()
  newlines = choice([string("\n"), string("\r")]) |> ignore()

  expression =
    repeat(choice([newlines, whitespace]))
    |> choice([env_var, symbol, access_operator])

  defparsec(:parse, expression)
end

Sanbase.SanLang.Parser.parse("_address2")
