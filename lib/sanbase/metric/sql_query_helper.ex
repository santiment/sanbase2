defmodule Sanbase.Metric.SqlQuery.Helper do
  @aggregations [:any, :sum, :avg, :min, :max, :last, :first, :median, :count]

  def aggregations(), do: @aggregations

  def aggregation(:last, value_column, dt_column), do: "argMax(#{value_column}, #{dt_column})"
  def aggregation(:first, value_column, dt_column), do: "argMin(#{value_column}, #{dt_column})"
  def aggregation(aggr, value_column, _dt_column), do: "#{aggr}(#{value_column})"
end
