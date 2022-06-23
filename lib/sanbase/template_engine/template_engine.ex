defmodule Sanbase.TemplateEngine do
  @moduledoc ~s"""
  Produce a string value from a given template and key-value enumerable.
  All occurances in the template that are enclosed in double braces are replaced
  with the corersponding values from KV enumerable.

  Example:
    iex> Sanbase.TemplateEngine.run("My name is {{name}}", %{name: "San"})
    "My name is San"

    iex> Sanbase.TemplateEngine.run("{{a}}{{b}}{{a}}{{a}}", %{a: "1", b: 2})
    "1211"

    iex> Sanbase.TemplateEngine.run("SmallNum: {{small_num}}", %{small_num: 100})
    "SmallNum: 100"

    iex> Sanbase.TemplateEngine.run("MediumNum: {{medium_num}}", %{medium_num: 100000})
    "MediumNum: 100000"

    iex> Sanbase.TemplateEngine.run("Human Readable MediumNum: {{medium_num}}", %{medium_num: 100000, human_readable: [:medium_num]})
    "Human Readable MediumNum: 100,000.00"

    iex> Sanbase.TemplateEngine.run("BigNum: {{big_num}}", %{big_num: 999999999999})
    "BigNum: 999999999999"


    iex> Sanbase.TemplateEngine.run("Human Readable BigNum: {{big_num}}", %{big_num: 999999999999, human_readable: [:big_num]})
    "Human Readable BigNum: 1,000.00 Billion"
  """

  @spec run(String.t(), map) :: String.t()
  def run(template, kv) do
    {human_readable_map, kv} = Map.split(kv, [:human_readable])

    human_readable_mapset =
      Map.get(human_readable_map, :human_readable, [])
      |> MapSet.new()

    Enum.reduce(kv, template, fn {key, value}, acc ->
      replace(acc, key, value, human_readable_mapset)
    end)
  end

  defp replace(string, key, value, human_readable_mapset) do
    String.replace(string, "{{#{key}}}", fn _ ->
      case key in human_readable_mapset do
        true -> value |> human_readable |> to_string()
        false -> value |> to_string()
      end
    end)
  end

  # Numbers below 1000 are not changed
  # Numbers between 1000 and 1000000 are delimited: 999,523.00, 123,529.12
  # Number bigger than 1000000 are made human readable: 1.54 Million, 85.00 Billion
  defp human_readable(data) do
    case data do
      num when is_number(num) and (num >= 1_000_000 or num <= -1_000_000) ->
        Number.Human.number_to_human(num)

      num when is_number(num) and (num >= 1000 or num <= -1000) ->
        Number.Delimit.number_to_delimited(num)

      num when is_number(num) and (num > -1 and num < 1) ->
        Number.Delimit.number_to_delimited(num, precision: 8)

      num when is_float(num) ->
        Number.Delimit.number_to_delimited(num, precision: 2)

      num when is_integer(num) ->
        Integer.to_string(num)
    end
  end
end
