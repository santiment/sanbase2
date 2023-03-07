defmodule Sanbase.Metric.SqlQuery.Helper do
  @aggregations [:any, :sum, :avg, :min, :max, :last, :first, :median, :count, :ohlc]
  @supported_interval_functions [
    "toStartOfDay",
    "toStartOfWeek",
    "toStartOfMonth",
    "toStartOfQuarter",
    "toStartOfYear",
    "toMonday",
    "toStartOfHour"
  ]

  @interval_function_to_equal_interval %{
    "toStartOfDay" => "1d",
    "toStartOfWeek" => "7d",
    "toStartOfMonth" => "30d",
    "toStartOfQuarter" => "90d",
    "toStartOfYear" => "365d",
    "toMonday" => "7d",
    "toStartOfHour" => "1h"
  }

  # when computing graphql complexity the function need to be transformed to the
  # equivalent interval so it can be computed
  def interval_function_to_equal_interval(), do: @interval_function_to_equal_interval

  def supported_interval_functions(), do: @supported_interval_functions

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

  def to_unix_timestamp(interval, dt_column, opts \\ [])

  def to_unix_timestamp(
        <<digit::utf8, _::binary>> = _interval,
        dt_column,
        opts
      )
      when digit in ?0..?9 do
    arg_name = Keyword.fetch!(opts, :argument_name)

    "toUnixTimestamp(intDiv(toUInt32(toDateTime(#{dt_column})), {{#{arg_name}}}) * {{#{arg_name}}})"
  end

  def to_unix_timestamp(function, dt_column, opts)
      when function in @supported_interval_functions do
    arg_name = Keyword.fetch!(opts, :argument_name)

    "if({{#{arg_name}}} = {{#{arg_name}}}, toUnixTimestamp(toDateTime(#{function}(#{dt_column}))), null)"
  end

  def to_unix_timestamp_from_number(<<digit::utf8, _::binary>> = _interval, opts \\ [])
      when digit in ?0..?9 do
    interval_name = Keyword.get(opts, :interval_argument_name, "interval")
    from_name = Keyword.get(opts, :from_argument_name, "from")

    "toUnixTimestamp(intDiv(toUInt32({{#{from_name}}} + number * {{#{interval_name}}}), {{#{interval_name}}}) * {{#{interval_name}}})"
  end

  def aggregation(:ohlc, value_column, dt_column) do
    """
    argMin(#{value_column}, #{dt_column}) AS open,
    max(#{value_column}) AS high,
    min(#{value_column}) AS low,
    argMax(#{value_column}, #{dt_column}) AS close
    """
  end

  def aggregation(:last, value_column, dt_column),
    do: "argMax(#{value_column}, #{dt_column})"

  def aggregation(:first, value_column, dt_column),
    do: "argMin(#{value_column}, #{dt_column})"

  def aggregation(:count, value_column, _dt_column),
    do: "coalesce(toFloat64(count(#{value_column})), 0.0)"

  def aggregation(:sum, value_column, _dt_column),
    do: "sumKahan(#{value_column})"

  def aggregation(aggr, value_column, _dt_column),
    do: "#{aggr}(#{value_column})"

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
    arg_name = Keyword.fetch!(opts, :argument_name)

    "asset_id IN ( SELECT asset_id FROM asset_metadata FINAL PREWHERE name = {{#{arg_name}}} LIMIT 1 )"
  end

  def asset_id_filter(%{slug: slugs}, opts) when is_list(slugs) do
    arg_name = Keyword.fetch!(opts, :argument_name)

    "asset_id IN ( SELECT DISTINCT(asset_id) FROM asset_metadata FINAL PREWHERE name IN ({{#{arg_name}}}) )"
  end

  def asset_id_filter(%{contract_address: contract_address}, opts)
      when is_binary(contract_address) do
    arg_name = Keyword.fetch!(opts, :argument_name)

    "asset_id IN ( SELECT asset_id FROM asset_metadata FINAL PREWHERE has(contract_addresses, {{#{arg_name}}}) LIMIT 1 )"
  end

  def asset_id_filter(_, opts) do
    case Keyword.get(opts, :allow_missing_slug, false) do
      true -> "1 = 1"
      false -> raise("Missing slug in asset_id_filter")
    end
  end

  def metric_id_filter(metric, opts) when is_binary(metric) do
    arg_name = Keyword.fetch!(opts, :argument_name)

    "metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = {{#{arg_name}}} LIMIT 1 )"
  end

  def metric_id_filter(metrics, opts) when is_list(metrics) do
    arg_name = Keyword.fetch!(opts, :argument_name)

    "metric_id IN ( SELECT DISTINCT(metric_id) FROM metric_metadata FINAL PREWHERE name IN ({{#{arg_name}}}) )"
  end

  def signal_id_filter(%{signal: signal}, opts) when is_binary(signal) do
    arg_name = Keyword.fetch!(opts, :argument_name)

    "signal_id = ( SELECT signal_id FROM signal_metadata FINAL PREWHERE name = {{#{arg_name}}} LIMIT 1 )"
  end

  def signal_id_filter(%{signal: signals}, opts) when is_list(signals) do
    arg_name = Keyword.fetch!(opts, :argument_name)

    "signal_id IN ( SELECT DISTINCT(signal_id) FROM signal_metadata FINAL PREWHERE name IN ({{#{arg_name}}}) )"
  end

  def signal_id_filter(_, opts) do
    case Keyword.get(opts, :allow_missing_signal, false) do
      true -> "1 = 1"
      false -> raise("Missing signal in signal_id_filter")
    end
  end

  def label_id_by_label_fqn_filter(label_fqn, opts) when is_binary(label_fqn) do
    arg_name = Keyword.fetch!(opts, :argument_name)

    "label_id = dictGetUInt64('default.label_ids_dict', 'label_id', tuple({{#{arg_name}}}))"
  end

  def label_id_by_label_fqn_filter(label_fqns, opts) when is_list(label_fqns) do
    arg_name = Keyword.fetch!(opts, :argument_name)

    "label_id IN (
      SELECT dictGetUInt64('default.label_ids_dict', 'label_id', tuple(fqn)) AS label_id
      FROM system.one
      ARRAY JOIN [{{#{arg_name}}}] AS fqn
    )"
  end

  def label_id_by_label_key_filter(label_key, opts) when is_binary(label_key) do
    arg_name = Keyword.fetch!(opts, :argument_name)

    "label_id IN (SELECT label_id FROM label_metadata PREWHERE key = {{#{arg_name}}})"
  end

  def label_id_by_label_key_filter(label_keys, opts) when is_list(label_keys) do
    arg_name = Keyword.fetch!(opts, :argument_name)

    "label_id IN (SELECT label_id FROM label_metadata PREWHERE key IN ({{#{arg_name}}}))"
  end

  # Add additional `=`/`in` filters to the query. This is mostly used with labeled
  # metrics where additional column filters must be applied.
  def additional_filters([], params, _opts), do: {"", params}

  def additional_filters(filters, params, opts) do
    {filters_str_list, params} =
      Enum.reduce(filters, {[], params}, fn {column, value}, {list_acc, params_acc} ->
        {filter_str, updated_params} = do_additional_filters(column, value, params_acc)

        {[filter_str | list_acc], updated_params}
      end)

    filters_string = filters_str_list |> Enum.reverse() |> Enum.join(" AND\n")

    filters_string =
      case Keyword.get(opts, :trailing_and, false) do
        false -> filters_string
        true -> filters_string <> " AND"
      end

    {filters_string, params}
  end

  @spec dt_to_unix(:from | :to, DateTime.t()) :: integer()
  def dt_to_unix(:from, dt) do
    Enum.max([dt, ~U[2009-01-01 00:00:00Z]], DateTime) |> DateTime.to_unix()
  end

  def dt_to_unix(:to, dt) do
    Enum.min([dt, DateTime.utc_now()], DateTime) |> DateTime.to_unix()
  end

  def timerange_parameters(from, to) do
    to = Enum.min_by([to, Timex.now()], &DateTime.to_unix/1)
    from_unix = dt_to_unix(:from, from)
    to_unix = dt_to_unix(:to, to)

    {from_unix, to_unix}
  end

  def timerange_parameters(from, to, interval) do
    from_unix = dt_to_unix(:from, from)
    to_unix = dt_to_unix(:to, to)

    interval_sec = Sanbase.DateTimeUtils.str_to_sec(interval)
    span = div(to_unix - from_unix, interval_sec) |> max(1)

    {from_unix, to_unix, interval_sec, span}
  end

  # Private functions

  defp do_additional_filters(:label_fqn, [value | _] = list, params) when is_binary(value) do
    pos = map_size(params) + 1
    label_fqn_key = "label_fqn_#{pos}"

    str = "label_id IN (
      SELECT dictGetUInt64('default.label_ids_dict', 'label_id', tuple(fqn)) AS label_id
      FROM system.one
      ARRAY JOIN [{{#{label_fqn_key}}}] AS fqn
    )"
    {str, Map.put(params, label_fqn_key, list)}
  end

  defp do_additional_filters(:label_fqn, value, params)
       when is_binary(value) do
    pos = map_size(params) + 1
    label_fqn_key = "label_fqn_#{pos}"

    str =
      "label_id = dictGetUInt64('default.label_ids_dict', 'label_id', tuple({{#{label_fqn_key}}}}))"

    {str, Map.put(params, label_fqn_key, value)}
  end

  defp do_additional_filters(column, [value | _] = list, params)
       when is_binary(value) do
    pos = map_size(params) + 1
    filter_key = "filter_#{column}_#{pos}"

    str = "lower(#{column}) IN ({{#{filter_key}}})"
    list = Enum.map(list, &String.downcase/1)

    {str, Map.put(params, filter_key, list)}
  end

  defp do_additional_filters(column, [value | _] = list, params)
       when is_number(value) do
    pos = map_size(params) + 1
    filter_key = "filter_#{column}_#{pos}"

    str = "#{column} IN ({{#{filter_key}}})"
    {str, Map.put(params, filter_key, list)}
  end

  defp do_additional_filters(column, value, params) when is_binary(value) do
    pos = map_size(params) + 1
    filter_key = "filter_#{column}_#{pos}"

    str = "lower(#{column}) = {{#{filter_key}}}"

    {str, Map.put(params, filter_key, String.downcase(value))}
  end

  defp do_additional_filters(column, value, params) when is_number(value) do
    pos = map_size(params) + 1
    filter_key = "filter_#{column}_#{pos}"

    str = "#{column} = {{#{filter_key}}}"
    {str, Map.put(params, filter_key, value)}
  end
end
