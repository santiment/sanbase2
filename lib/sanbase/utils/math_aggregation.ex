defmodule Sanbase.MathAggregation do
  def compute(list, aggregation, fun \\ & &1)
  def compute(list, :max, fun), do: Enum.map(list, fun) |> Enum.max()
  def compute(list, :min, fun), do: Enum.map(list, fun) |> Enum.min()
  def compute(list, :avg, fun), do: Enum.map(list, fun) |> Sanbase.Math.mean()
  def compute(list, :median, fun), do: Enum.map(list, fun) |> Sanbase.Math.median()
  def compute(list, :count, _fun), do: Enum.count(list)
  def compute(list, :sum, fun), do: Enum.map(list, fun) |> Enum.sum()
  def compute(list, :first, fun), do: Enum.map(list, fun) |> List.first()
  def compute(list, :last, fun), do: Enum.map(list, fun) |> List.last()

  def compute(list, :ohlc, fun) do
    %{
      open: compute(list, :first, fun),
      high: compute(list, :max, fun),
      low: compute(list, :min, fun),
      close: compute(list, :last, fun)
    }
  end
end
