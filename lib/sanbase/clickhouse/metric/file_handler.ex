defmodule Sanbase.Clickhouse.MetricAdapter.FileHandler do
  @moduledoc false

  require Sanbase.Break, as: Break

  defmodule Helper do
    import Sanbase.DateTimeUtils, only: [interval_to_str: 1]

    alias Sanbase.TemplateEngine

    def name_to_field_map(map, field, opts \\ []) do
      Break.if_kw_invalid?(opts, valid_keys: [:transform_fn, :required?])

      transform_fn = Keyword.get(opts, :transform_fn, &Function.identity/1)
      required? = Keyword.get(opts, :required?, true)

      map
      |> Enum.into(%{}, fn
        %{"name" => name, ^field => value} ->
          {name, transform_fn.(value)}

        %{"name" => name} ->
          if required? do
            # TODO: This logic is the same as it is in the signal file handler,
            # with the exeption of the words in the error.
            # It should be extracted to avoid code duplication.
            Break.break("The field \"#{field}\" in the #{name} metric is required")
          else
            {name, nil}
          end
      end)
    end

    def resolve_metric_aliases(aliases, metric) do
      duplicates =
        aliases
        |> Enum.map(&Map.put(metric, "name", &1))

      [metric | duplicates]
    end

    def resolve_timebound_metrics(metric_map, timebound_values) do
      %{
        "name" => name,
        "metric" => metric,
        "human_readable_name" => human_readable_name
      } = metric_map

      timebound_values
      |> Enum.map(fn timebound ->
        %{
          metric_map
          | "name" => TemplateEngine.run(name, %{timebound: timebound}),
            "metric" => TemplateEngine.run(metric, %{timebound: timebound}),
            "human_readable_name" =>
              TemplateEngine.run(
                human_readable_name,
                %{timebound_human_readable: interval_to_str(timebound)}
              )
        }
      end)
    end

    def expand_timebound_metrics(metrics_json_pre_timebound_expand) do
      Enum.flat_map(
        metrics_json_pre_timebound_expand,
        fn metric ->
          case Map.get(metric, "timebound") do
            nil ->
              [metric]

            timebound_values ->
              resolve_timebound_metrics(metric, timebound_values)
          end
        end
      )
    end

    def access_level_to_atom(access) when is_binary(access), do: String.to_atom(access)

    def access_level_to_atom(access) when is_map(access) do
      Enum.into(access, %{}, fn {k, v} -> {k, String.to_atom(v)} end)
    end

    def resolve_access_level(access) when is_atom(access), do: access

    def resolve_access_level(access) when is_map(access) do
      case access do
        %{"historical" => :free, "realtime" => :free} -> :free
        _ -> :restricted
      end
    end
  end

  # Structure
  #  This JSON file contains a list of metrics available in ClickHouse.
  #  For every metric we have:
  #  metric - the original metric name, the very same that is used in the
  #  ClickHouse metric_metadata table
  #  alias - the name we are exposing the metric from the API. It is a more
  #  access - whether the metric is completely free or some time restrictions
  #  should be applied
  #  user-friendly name than the metric name
  #  aggregation - the default aggregation that is applied to combine the values
  #  if the data is queried with interval bigger than 'min_interval'
  #  min-interval - the minimal interval the data is available for
  #  table - the table name in ClickHouse where the metric is stored
  # Ordering
  #  The metrics order in this list is not important. For consistency and
  #  to be easy-readable, the same metric with different time-bound are packed
  #  together. In descending order we have the time-bound from biggest to
  #  smallest.
  #  `time-bound` means that the metric is calculated by taking into account
  #  only the coins/tokens that moved in the past N days/years

  # @external_resource is registered with `accumulate: true`, so it holds all files
  @external_resource Path.join(__DIR__, "metric_files/available_v2_metrics.json")
  @external_resource Path.join(__DIR__, "metric_files/change_metrics.json")
  @external_resource Path.join(__DIR__, "metric_files/defi_metrics.json")
  @external_resource Path.join(__DIR__, "metric_files/derivatives_metrics.json")
  @external_resource Path.join(__DIR__, "metric_files/eth2_metrics.json")
  @external_resource Path.join(__DIR__, "metric_files/exchange_metrics.json")
  @external_resource Path.join(__DIR__, "metric_files/histogram_metrics.json")
  @external_resource Path.join(__DIR__, "metric_files/holders_metrics.json")
  @external_resource Path.join(__DIR__, "metric_files/label_metrics.json")
  @external_resource Path.join(__DIR__, "metric_files/labeled_balance_metrics.json")
  @external_resource Path.join(__DIR__, "metric_files/labeled_between_labels_flow_metrics.json")
  @external_resource Path.join(__DIR__, "metric_files/labeled_exchange_flow_metrics.json")
  @external_resource Path.join(__DIR__, "metric_files/makerdao_metrics.json")
  @external_resource Path.join(__DIR__, "metric_files/social_metrics.json")
  @external_resource Path.join(__DIR__, "metric_files/table_structured_metrics.json")
  @external_resource Path.join(__DIR__, "metric_files/uniswap_metrics.json")
  @external_resource Path.join(__DIR__, "metric_files/labeled_holders_distribution_metrics.json")

  @metrics_json_pre_alias_expand Enum.reduce(@external_resource, [], fn file, acc ->
                                   (File.read!(file) |> Jason.decode!()) ++ acc
                                 end)

  @metrics_json_pre_timebound_expand Enum.flat_map(
                                       @metrics_json_pre_alias_expand,
                                       fn metric ->
                                         Map.get(metric, "aliases", [])
                                         |> Helper.resolve_metric_aliases(metric)
                                       end
                                     )

  @metrics_json Helper.expand_timebound_metrics(@metrics_json_pre_timebound_expand)
  @aggregations Sanbase.Metric.SqlQuery.Helper.aggregations()
  @metrics_data_type_map Helper.name_to_field_map(@metrics_json, "data_type",
                           transform_fn: &String.to_atom/1
                         )

  @name_to_metric_map Helper.name_to_field_map(@metrics_json, "metric")
  @metric_to_name_map @name_to_metric_map |> Map.new(fn {k, v} -> {v, k} end)
  @access_map Helper.name_to_field_map(@metrics_json, "access",
                transform_fn: &Helper.access_level_to_atom/1
              )

  @table_map Helper.name_to_field_map(@metrics_json, "table")
  @aggregation_map Helper.name_to_field_map(@metrics_json, "aggregation",
                     transform_fn: &String.to_atom/1
                   )

  @min_interval_map Helper.name_to_field_map(@metrics_json, "min_interval")
  @min_plan_map Helper.name_to_field_map(@metrics_json, "min_plan",
                  transform_fn: fn plan_map ->
                    Enum.into(plan_map, %{}, fn {k, v} -> {k, String.to_atom(v)} end)
                  end
                )

  @human_readable_name_map Helper.name_to_field_map(@metrics_json, "human_readable_name")
  @metric_version_map Helper.name_to_field_map(@metrics_json, "version")
  @metrics_label_map Helper.name_to_field_map(@metrics_json, "label", required?: false)
  @incomplete_data_map Helper.name_to_field_map(@metrics_json, "has_incomplete_data")
  @selectors_map Helper.name_to_field_map(
                   @metrics_json,
                   "selectors",
                   transform_fn: fn list ->
                     Enum.map(list, &String.to_atom/1)
                   end
                 )

  @metrics_list @metrics_json |> Enum.map(fn %{"name" => name} -> name end)
  @metrics_mapset MapSet.new(@metrics_list)

  Enum.group_by(
    @metrics_json_pre_alias_expand,
    fn metric -> {metric["metric"], metric["data_type"]} end
  )
  |> Map.values()
  |> Enum.filter(fn grouped_metrics -> Enum.count(grouped_metrics) > 1 end)
  |> Enum.each(fn duplicate_metrics ->
    Break.break("""
      Duplicate metrics found, consider using the aliases field:
      `aliases: ["name1", "name2", ...]`
      These metrics are: #{inspect(duplicate_metrics)}
    """)
  end)

  case Enum.filter(@aggregation_map, fn {_, aggr} -> aggr not in @aggregations end) do
    [] ->
      :ok

    metrics ->
      Break.break("""
      There are metrics defined in the metric files that have not supported aggregation.
      These metrics are: #{inspect(metrics)}
      """)
  end

  def aggregations(), do: @aggregations
  def access_map(), do: @access_map
  def table_map(), do: @table_map
  def metrics_mapset(), do: @metrics_mapset
  def aggregation_map(), do: @aggregation_map
  def min_interval_map(), do: @min_interval_map
  def min_plan_map(), do: @min_plan_map
  def name_to_metric_map(), do: @name_to_metric_map
  def metric_to_name_map(), do: @metric_to_name_map
  def human_readable_name_map(), do: @human_readable_name_map
  def metric_version_map(), do: @metric_version_map
  def metrics_data_type_map(), do: @metrics_data_type_map
  def incomplete_data_map(), do: @incomplete_data_map
  def selectors_map(), do: @selectors_map

  def metrics_label_map(), do: @metrics_label_map

  def metrics_with_access(level) when level in [:free, :restricted] do
    @access_map
    |> Enum.filter(fn {_metric, restrictions} ->
      Helper.resolve_access_level(restrictions) === level
    end)
    |> Enum.map(&elem(&1, 0))
  end

  def metrics_with_data_type(type) do
    @metrics_data_type_map
    |> Enum.filter(fn {_metric, data_type} -> data_type == type end)
    |> Enum.map(&elem(&1, 0))
  end
end
