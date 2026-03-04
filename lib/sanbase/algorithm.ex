defmodule Sanbase.Algorithm do
  @doc ~s"""
  Group a sorted list of dates into ranges of consecutive days.

  Returns a list of `{start_date, end_date}` tuples where each tuple
  represents a maximal run of consecutive dates.

  ## Examples

      iex> dates = [~D[2023-01-01], ~D[2023-01-02], ~D[2023-01-03], ~D[2023-01-05], ~D[2023-01-06]]
      iex> Sanbase.Algorithm.consecutive_ranges(dates)
      [{~D[2023-01-01], ~D[2023-01-03]}, {~D[2023-01-05], ~D[2023-01-06]}]

      iex> Sanbase.Algorithm.consecutive_ranges([~D[2023-01-01]])
      [{~D[2023-01-01], ~D[2023-01-01]}]

      iex> Sanbase.Algorithm.consecutive_ranges([])
      []
  """
  @spec consecutive_ranges([Date.t()]) :: [{Date.t(), Date.t()}]
  def consecutive_ranges([]), do: []

  def consecutive_ranges([first | rest]) do
    rest
    |> Enum.reduce({first, first, []}, fn date, {start, prev, acc} ->
      if Date.diff(date, prev) == 1 do
        {start, date, acc}
      else
        {date, date, [{start, prev} | acc]}
      end
    end)
    |> then(fn {start, prev, acc} -> [{start, prev} | acc] end)
    |> Enum.reverse()
  end
end
