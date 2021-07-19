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
  def aggregation(:sum, value_column, _dt_column), do: "sumKahan(#{value_column})"
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
    asset_id IN ( SELECT DISTINCT(asset_id) FROM asset_metadata FINAL PREWHERE name IN (?#{arg_position}) )
    """
  end

  def metric_id_filter(metric, opts) when is_binary(metric) do
    arg_position = Keyword.fetch!(opts, :argument_position)

    """
    metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = ?#{arg_position} LIMIT 1 )
    """
  end

  def metric_id_filter(metrics, opts) when is_list(metrics) do
    arg_position = Keyword.fetch!(opts, :argument_position)

    """
    metric_id IN ( SELECT DISTINCT(metric_id) FROM metric_metadata FINAL PREWHERE name IN (?#{arg_position}) )
    """
  end

  # Add additional `=`/`in` filters to the query. This is mostly used with labeled
  # metrics where additional column filters must be applied.
  def additional_filters([], _opts), do: []

  def additional_filters(filters, opts) do
    filters_string =
      filters
      |> Enum.map(fn
        {column, [value | _] = list} when is_list(list) and is_binary(value) ->
          coma_separated = list |> Enum.map(&"'#{&1}'") |> Enum.join(",")
          ~s/lower(#{column}) IN (#{coma_separated})/

        {column, [value | _] = list} when is_list(list) and is_number(value) ->
          coma_separated = Enum.join(list, ",")
          ~s/#{column} IN (#{coma_separated})/

        {column, value} when is_binary(value) ->
          ~s/lower(#{column}) = '#{value |> String.downcase()}'/

        {column, value} when is_number(value) ->
          ~s/#{column} = #{value}/
      end)
      |> Enum.join(" AND\n")

    filters_string <> " AND"

    case Keyword.get(opts, :trailing_and, false) do
      false -> filters_string
      true -> filters_string <> " AND"
    end
  end
end
