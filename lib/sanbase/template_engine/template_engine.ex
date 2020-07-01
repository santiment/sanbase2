defmodule Sanbase.TemplateEngine do
  @moduledoc ~s"""
  """

  def run(template, kv) do
    {human_readable_map, kv} = Map.split(kv, [:human_readable])
    human_readable = Map.get(human_readable_map, :human_readable, [])

    Enum.reduce(kv, template, fn {key, value}, acc ->
      String.replace(acc, "{{#{key}}}", fn _ ->
        case key in human_readable do
          true -> value |> human_readable |> to_string()
          false -> value |> to_string()
        end
      end)
    end)
  end

  # Numbers below 1000 are not changed
  # Numbers between 1000 and 1000000 are delimited: 999,523.00, 123,529.12
  # Number bigger than 1000000 are made human readable: 1.54 Million, 85.00 Billion
  defp human_readable(data) do
    case data do
      num when is_number(num) and num >= 1_000_000 -> Number.Human.number_to_human(num)
      num when is_number(num) and num >= 1000 -> Number.Delimit.number_to_delimited(num)
      _ -> data
    end
  end
end
