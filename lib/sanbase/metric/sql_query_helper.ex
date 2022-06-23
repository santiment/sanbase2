defmodule Sanbase.Metric.SqlQuery.Helper do
  @aggregations [:any, :sum, :avg, :min, :max, :last, :first, :median, :count, :ohlc]

  @type operator ::
          :inside_channel
          | :outside_channel
          | :less_than
          | :less_than_or_equal_to
          | :greater_than
          | :greater_than_or_equal_to
          | :inside_channel_inclusive
          | :inside_channel_exclusive
          | :outside_channel_inclusive
          | :outside_channel_exclusive

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

  def generate_comparison_string(column, :inside_channel, value),
    do: generate_comparison_string(column, :inside_channel_inclusive, value)

  def generate_comparison_string(column, :outside_channel, value),
    do: generate_comparison_string(column, :outside_channel_inclusive, value)

  def generate_comparison_string(column, :less_than, threshold)
      when is_number(threshold),
      do: "#{column} < #{threshold}"

  def generate_comparison_string(column, :less_than_or_equal_to, threshold)
      when is_number(threshold),
      do: "#{column} <= #{threshold}"

  def generate_comparison_string(column, :greater_than, threshold)
      when is_number(threshold),
      do: "#{column} > #{threshold}"

  def generate_comparison_string(column, :greater_than_or_equal_to, threshold)
      when is_number(threshold),
      do: "#{column} >= #{threshold}"

  def generate_comparison_string(column, :inside_channel_inclusive, [low, high])
      when is_number(low) and is_number(high),
      do: "#{column} >= #{low} AND #{column} <= #{high}"

  def generate_comparison_string(column, :inside_channel_exclusive, [low, high])
      when is_number(low) and is_number(high),
      do: "#{column} > #{low} AND #{column} < #{high}"

  def generate_comparison_string(column, :outside_channel_inclusive, [low, high])
      when is_number(low) and is_number(high),
      do: "#{column} <= #{low} OR #{column} >= #{high}"

  def generate_comparison_string(column, :outside_channel_exclusive, [low, high])
      when is_number(low) and is_number(high),
      do: "#{column} < #{low} OR #{column} > #{high}"

  def asset_id_filter(%{slug: slug}, opts) when is_binary(slug) do
    arg_position = Keyword.fetch!(opts, :argument_position)

    "asset_id = ( SELECT asset_id FROM asset_metadata FINAL PREWHERE name = ?#{arg_position} LIMIT 1 )"
  end

  def asset_id_filter(%{slug: slugs}, opts) when is_list(slugs) do
    arg_position = Keyword.fetch!(opts, :argument_position)

    "asset_id IN ( SELECT DISTINCT(asset_id) FROM asset_metadata FINAL PREWHERE name IN (?#{arg_position}) )"
  end

  def asset_id_filter(_, opts) do
    case Keyword.get(opts, :allow_missing_slug, false) do
      true -> "1 = 1"
      false -> raise("Missing slug in asset_id_filter")
    end
  end

  def metric_id_filter(metric, opts) when is_binary(metric) do
    arg_position = Keyword.fetch!(opts, :argument_position)

    "metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = ?#{arg_position} LIMIT 1 )"
  end

  def metric_id_filter(metrics, opts) when is_list(metrics) do
    arg_position = Keyword.fetch!(opts, :argument_position)

    "metric_id IN ( SELECT DISTINCT(metric_id) FROM metric_metadata FINAL PREWHERE name IN (?#{arg_position}) )"
  end

  def label_id_by_label_fqn_filter(label_fqn, opts) when is_binary(label_fqn) do
    arg_position = Keyword.fetch!(opts, :argument_position)
    "label_id = dictGetUInt64('default.label_ids_dict', 'label_id', tuple(?#{arg_position}))"
  end

  def label_id_by_label_fqn_filter(label_fqns, opts) when is_list(label_fqns) do
    arg_position = Keyword.fetch!(opts, :argument_position)

    "label_id IN (
      SELECT dictGetUInt64('default.label_ids_dict', 'label_id', tuple(fqn)) AS label_id
      FROM system.one
      ARRAY JOIN [?#{arg_position}] AS fqn
    )"
  end

  def label_id_by_label_key_filter(label_key, opts) when is_binary(label_key) do
    arg_position = Keyword.fetch!(opts, :argument_position)
    "label_id IN (SELECT label_id FROM label_metadata PREWHERE key = ?#{arg_position})"
  end

  def label_id_by_label_key_filter(label_keys, opts) when is_list(label_keys) do
    arg_position = Keyword.fetch!(opts, :argument_position)
    "label_id IN (SELECT label_id FROM label_metadata PREWHERE key IN (?#{arg_position}))"
  end

  # Add additional `=`/`in` filters to the query. This is mostly used with labeled
  # metrics where additional column filters must be applied.
  def additional_filters([], args, _opts), do: {"", args}

  def additional_filters(filters, args, opts) do
    {filters_str_list, args} =
      Enum.reduce(filters, {[], args}, fn {column, value}, {list_acc, args_acc} ->
        {filter_str, updated_args} = do_additional_filters(column, value, args_acc)

        {[filter_str | list_acc], updated_args}
      end)

    filters_string = filters_str_list |> Enum.reverse() |> Enum.join(" AND\n")

    filters_string =
      case Keyword.get(opts, :trailing_and, false) do
        false -> filters_string
        true -> filters_string <> " AND"
      end

    {filters_string, args}
  end

  def dt_to_unix(:from, dt) do
    Enum.max([dt, ~U[2009-01-01 00:00:00Z]], DateTime) |> DateTime.to_unix()
  end

  def dt_to_unix(:to, dt) do
    Enum.min([dt, DateTime.utc_now()], DateTime) |> DateTime.to_unix()
  end

  # Private functions

  defp do_additional_filters(:label_fqn, value, args) when is_binary(value) do
    pos = length(args) + 1
    str = "label_id IN (
      SELECT dictGetUInt64('default.label_ids_dict', 'label_id', tuple(fqn)) AS label_id
      FROM system.one
      ARRAY JOIN [?#{pos}] AS fqn
    )"
    args = args ++ [value]
    {str, args}
  end

  defp do_additional_filters(:label_fqn, [value | _] = list, args) when is_binary(value) do
    pos = length(args) + 1
    str = "label_id = dictGetUInt64('default.label_ids_dict', 'label_id', tuple(?#{pos}))"
    args = args ++ [list]
    {str, args}
  end

  defp do_additional_filters(column, [value | _] = list, args)
       when is_binary(value) do
    pos = length(args) + 1
    str = "lower(#{column}) IN (?#{pos})"
    list = Enum.map(list, &String.downcase/1)
    args = args ++ [list]
    {str, args}
  end

  defp do_additional_filters(column, [value | _] = list, args) when is_number(value) do
    pos = length(args) + 1
    str = "#{column} IN (?#{pos})"
    args = args ++ [list]
    {str, args}
  end

  defp do_additional_filters(column, value, args) when is_binary(value) do
    pos = length(args) + 1
    str = "lower(#{column}) = ?#{pos}"
    args = args ++ [String.downcase(value)]
    {str, args}
  end

  defp do_additional_filters(column, value, args) when is_number(value) do
    pos = length(args) + 1
    str = "#{column} = ?#{pos}"
    args = args ++ [value]
    {str, args}
  end
end
