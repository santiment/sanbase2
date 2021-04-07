defmodule Sanbase.Metric.SqlQuery.Helper do
  @aggregations [:any, :sum, :avg, :min, :max, :last, :first, :median, :count, :ohlc]

  def aggregations(), do: @aggregations

  def aggregation(:ohlc, value_column, dt_column) do
    """
    argMin(#{value_column}, #{dt_column}) AS open,
    max(#{value_column}) AS high,
    min(#{value_column}) AS low,
    argMax(#{value_column}, #{dt_column}) AS close
    """
  end

  def aggregation(:last, value_column, dt_column), do: "argMax(#{value_column}, #{dt_column})"
  def aggregation(:first, value_column, dt_column), do: "argMin(#{value_column}, #{dt_column})"
  def aggregation(:count, value_column, _dt_column), do: "coalesce(count(#{value_column}), 0)"
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

  def asset_id_filter(slug, opts) when is_binary(slug) do
    arg_position = Keyword.fetch!(opts, :argument_position)

    """
    asset_id = ( SELECT asset_id FROM asset_metadata FINAL PREWHERE name = ?#{arg_position} LIMIT 1 )
    """
  end

  def asset_id_filter(slugs, opts) when is_list(slugs) do
    arg_position = Keyword.fetch!(opts, :argument_position)

    """
    asset_id IN ( SELECT DISTINCT(asset_id) FROM asset_metadata FINAL PREWHERE name IN (?#{
      arg_position
    }) )
    """
  end
end
