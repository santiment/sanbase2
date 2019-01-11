defmodule Sanbase.DateTimeUtils.ExAdmin do
  def to_naive(%{
        day: day,
        hour: hour,
        min: min,
        month: month,
        year: year
      })
      when is_binary(day) and is_binary(hour) and is_binary(min) and is_binary(month) and
             is_binary(year) do
    [day, hour, min, month, year] =
      [day, hour, min, month, year] |> Enum.map(&String.to_integer/1)

    NaiveDateTime.from_erl({{year, month, day}, {hour, min, 0}})
  end
end
