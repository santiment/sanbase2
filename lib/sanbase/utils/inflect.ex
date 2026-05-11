defmodule Sanbase.Utils.Inflect do
  @moduledoc """
  Minimal string inflection utilities (camelize, underscore).
  Vendored from the `inflex` package to remove an unmaintained dependency.

  Note: splits on `(?=[A-Z])` (before every uppercase letter), whereas Inflex
  split on `(?=[A-Z][a-z])` (only before uppercase followed by lowercase).
  The results are identical for standard snake_case and camelCase inputs.
  They differ only for consecutive-uppercase tokens like "getHTTPResponse"
  (ours: "getHTTPResponse", Inflex: "gethttpResponse") — this pattern does
  not appear in the codebase.
  """

  @doc """
  Converts a string or atom to UpperCamelCase.

      iex> Sanbase.Utils.Inflect.camelize("upper_camel_case")
      "UpperCamelCase"
  """
  def camelize(word), do: camelize(word, :upper)

  @doc """
  Converts a string or atom to CamelCase.

  Pass `:lower` to lower-case the first letter (lowerCamelCase).

      iex> Sanbase.Utils.Inflect.camelize("some_field", :lower)
      "someField"

      iex> Sanbase.Utils.Inflect.camelize("some_field", :upper)
      "SomeField"
  """
  def camelize(word, option) do
    word
    |> to_string()
    |> String.split(~r/[-_]|(?=[A-Z])/, trim: true)
    |> camelize_parts(option)
    |> Enum.join()
  end

  @doc """
  Converts a CamelCase or hyphenated string to snake_case.

      iex> Sanbase.Utils.Inflect.underscore("UpperCamelCase")
      "upper_camel_case"

      iex> Sanbase.Utils.Inflect.underscore("some-hyphenated")
      "some_hyphenated"
  """
  def underscore(word) do
    word
    |> to_string()
    |> Macro.underscore()
    |> String.replace("-", "_")
  end

  defp camelize_parts([], _), do: []
  defp camelize_parts([h | tail], :lower), do: [String.downcase(h) | camelize_parts(tail, :upper)]

  defp camelize_parts([h | tail], :upper),
    do: [String.capitalize(h) | camelize_parts(tail, :upper)]
end
