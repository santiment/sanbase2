defmodule Sanbase.MathAggregation do
  @moduledoc false
  def compute(list, aggregation, fun \\ & &1)
  def compute(list, :max, fun), do: list |> Enum.map(fun) |> Enum.max()
  def compute(list, :min, fun), do: list |> Enum.map(fun) |> Enum.min()
  def compute(list, :avg, fun), do: list |> Enum.map(fun) |> Sanbase.Math.mean()
  def compute(list, :median, fun), do: list |> Enum.map(fun) |> Sanbase.Math.median()
  def compute(list, :count, _fun), do: Enum.count(list)
  def compute(list, :sum, fun), do: list |> Enum.map(fun) |> Enum.sum()
  def compute(list, :first, fun), do: list |> Enum.map(fun) |> List.first()
  def compute(list, :last, fun), do: list |> Enum.map(fun) |> List.last()

  def compute(list, :ohlc, fun) do
    %{
      open: compute(list, :first, fun),
      high: compute(list, :max, fun),
      low: compute(list, :min, fun),
      close: compute(list, :last, fun)
    }
  end
end
