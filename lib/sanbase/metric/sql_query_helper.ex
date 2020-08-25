defmodule Sanbase.Metric.SqlQuery.Helper do
  @aggregations [:any, :sum, :avg, :min, :max, :last, :first, :median, :count]

  def aggregations(), do: @aggregations

  def aggregation(:last, value_column, dt_column), do: "argMax(#{value_column}, #{dt_column})"
  def aggregation(:first, value_column, dt_column), do: "argMin(#{value_column}, #{dt_column})"
  def aggregation(aggr, value_column, _dt_column), do: "#{aggr}(#{value_column})"

  def generate_comparison_string(column, :inside_channel, threshold),
    do: generate_comparison_string(column, :inside_channel_inclusive, threshold)

  def generate_comparison_string(column, :outside_channel, threshold),
    do: generate_comparison_string(column, :outside_channel_inclusive, threshold)

  def generate_comparison_string(column, :less_than, threshold), do: "#{column} < #{threshold}"

  def generate_comparison_string(column, :less_than_or_equal_to, threshold),
    do: "#{column} <= #{threshold}"

  def generate_comparison_string(column, :greater_than, threshold), do: "#{column} > #{threshold}"

  def generate_comparison_string(column, :greater_than_or_equal_to, threshold),
    do: "#{column} >= #{threshold}"

  def generate_comparison_string(column, :inside_channel_inclusive, [low, high]),
    do: "#{column} >= #{low} AND #{column} <= #{high}"

  def generate_comparison_string(column, :inside_channel_exclusive, [low, high]),
    do: "#{column} > #{low} AND #{column} < #{high}"

  def generate_comparison_string(column, :outside_channel_inclusive, [low, high]),
    do: "#{column} <= #{low} OR #{column} >= #{high}"

  def generate_comparison_string(column, :outside_channel_exclusive, [low, high]),
    do: "#{column} < #{low} OR #{column} > #{high}"
end
