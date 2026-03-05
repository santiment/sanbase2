defmodule Sanbase.Algorithm do
  @moduledoc "Utility algorithms for date and data processing."

  @doc ~s"""
  Group a list of dates into ranges of consecutive days.

  The input list is deduplicated and sorted before grouping, so it does not
  need to be pre-sorted or unique.

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

      iex> Sanbase.Algorithm.consecutive_ranges([~D[2023-01-03], ~D[2023-01-01], ~D[2023-01-02]])
      [{~D[2023-01-01], ~D[2023-01-03]}]

      iex> Sanbase.Algorithm.consecutive_ranges([~D[2023-01-01], ~D[2023-01-01], ~D[2023-01-02]])
      [{~D[2023-01-01], ~D[2023-01-02]}]
  """
  @spec consecutive_ranges([Date.t()]) :: [{Date.t(), Date.t()}]
  def consecutive_ranges([]), do: []

  def consecutive_ranges(dates) do
    [first | rest] = dates |> Enum.uniq() |> Enum.sort(Date)

    rest
    |> Enum.reduce({first, first, []}, fn date, {start, prev, acc} ->
      # No need to check for 0 as the Enum.uniq handles duplicates
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
