defmodule Sanbase.Clickhouse.MetricAdapter.FileHandler do
  @moduledoc false

  require Sanbase.Break, as: Break

  defmodule Helper do
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

    def expand_patterns(metrics_json) do
      metrics_json
      |> expand_parameters_metrics()
    end

    def expand_parameters_metrics(metrics_json) do
      Enum.flat_map(metrics_json, fn metric_map ->
        case Map.get(metric_map, "parameters") do
          nil ->
            [metric_map]

          parameters_list ->
            run_templates_on_parameters(parameters_list, metric_map)
        end
      end)
    end

    def atomize_access_level_value(access) when is_binary(access),
      do: String.to_existing_atom(access)

    def atomize_access_level_value(access) when is_map(access) do
      Enum.into(access, %{}, fn {k, v} -> {k, String.to_existing_atom(v)} end)
    end

    def resolve_access_level(access) when is_atom(access), do: access

    def resolve_access_level(access) when is_map(access) do
      case access do
        %{"historical" => :free, "realtime" => :free} -> :free
        _ -> :restricted
      end
    end

    defp run_templates_on_parameters(parameters_list, metric_map) do
      %{"name" => name, "human_readable_name" => human_name, "metric" => metric} =
        metric_map

      aliases = Map.get(metric_map, "aliases", [])

      Enum.map(parameters_list, fn parameters ->
        metric_map
        |> Map.put("name", TemplateEngine.run!(name, params: parameters))
        |> Map.put("metric", TemplateEngine.run!(metric, params: parameters))
        |> Map.put(
          "human_readable_name",
          TemplateEngine.run!(human_name, params: parameters)
        )
        |> Map.put(
          "aliases",
          Enum.map(aliases, &TemplateEngine.run!(&1, params: parameters))
        )
      end)
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
  path_to = fn file -> Path.join([__DIR__, "metric_files", file]) end
  path_to_deprecated = fn file -> Path.join([__DIR__, "metric_files", "deprecated", file]) end

  @external_resource path_to.("available_v2_metrics.json")
  @external_resource path_to.("change_metrics.json")
  @external_resource path_to.("defi_metrics.json")
  @external_resource path_to.("derivatives_metrics.json")
  @external_resource path_to.("eth2_metrics.json")
  @external_resource path_to.("exchange_metrics.json")
  @external_resource path_to.("ecosystem_aggregated_metrics.json")
  @external_resource path_to.("histogram_metrics.json")
  @external_resource path_to.("holders_metrics.json")
  @external_resource path_to.("label_based_metric_metrics.json")
  @external_resource path_to.("labeled_balance_metrics.json")
  @external_resource path_to.("labeled_intraday_metrics.json")
  @external_resource path_to.("makerdao_metrics.json")
  @external_resource path_to.("social_metrics.json")
  @external_resource path_to.("table_structured_metrics.json")
  @external_resource path_to.("uniswap_metrics.json")
  @external_resource path_to.("labeled_holders_distribution_metrics.json")
  @external_resource path_to.("active_holders_metrics.json")
  @external_resource path_to.("fixed_parameters_labelled_balance_metrics.json")

  # Hidden metrics
  # These metrics are available for fetching, but they do not appear in any
  # available metrics API calls
  @external_resource path_to.("hidden_social_metrics.json")

  # Deprecated metrics
  @external_resource path_to_deprecated.("deprecated_change_metrics.json")
  @external_resource path_to_deprecated.("deprecated_labeled_between_labels_flow_metrics.json")
  @external_resource path_to_deprecated.("deprecated_labeled_exchange_flow_metrics.json")
  @external_resource path_to_deprecated.("deprecated_social_metrics.json")

  @metrics_json_pre_alias_expand Enum.reduce(
                                   @external_resource,
                                   [],
                                   fn file, acc ->
                                     try do
                                       (File.read!(file) |> Jason.decode!()) ++ acc
                                     rescue
                                       e in [Jason.DecodeError] ->
                                         IO.warn("Jason decoding error in file #{file}")
                                         reraise e, __STACKTRACE__
                                     end
                                   end
                                 )

  def pre_alias(), do: @metrics_json_pre_alias_expand
  # Allow the same metric to be defined more than once if it differs in the `data_type`.
  # Also allow the same metric to be used if different `fixed_parameters` are provided.
  # In this case the metric is exposed with some of the parameters (like labels) already fixed,
  # like: balance of funds, balance of whales, etc.
  Enum.group_by(
    @metrics_json_pre_alias_expand,
    fn metric -> {metric["metric"], metric["data_type"], metric["fixed_parameters"]} end
  )
  |> Map.values()
  |> Enum.filter(fn grouped_metrics -> Enum.count(grouped_metrics) > 1 end)
  |> Enum.each(fn duplicate_metrics ->
    duplicate_metrics =
      Enum.map(duplicate_metrics, fn map -> Map.take(map, ["name", "metric"]) end)

    Break.break("""
      Duplicate metrics found, consider using the aliases field:
      `aliases: ["name1", "name2", ...]`
      These metrics are: #{inspect(duplicate_metrics)}
    """)
  end)

  @metrics_json_pre_expand_patterns Enum.flat_map(
                                      @metrics_json_pre_alias_expand,
                                      fn metric ->
                                        Map.get(metric, "aliases", [])
                                        |> Helper.resolve_metric_aliases(metric)
                                      end
                                    )

  @metrics_json_including_deprecated Helper.expand_patterns(@metrics_json_pre_expand_patterns)

  # The deprecated metrics are filtered at a later stage at runtime, not here at compile time.
  # This is because `hard_deprecate_after` can hold a future value and until then
  # it can still be used. The filtering is done in the Sanbase.Metric.Helper module
  # which is the one directly used by the Sanbase.Metric module.
  @metrics_json @metrics_json_including_deprecated

  @aggregations Sanbase.Metric.SqlQuery.Helper.aggregations()
  @metrics_data_type_map Helper.name_to_field_map(@metrics_json, "data_type",
                           transform_fn: &String.to_atom/1
                         )

  @name_to_metric_map Helper.name_to_field_map(@metrics_json, "metric")
  @metric_to_names_map @name_to_metric_map
                       |> Enum.group_by(fn {_k, v} -> v end, fn {k, _v} -> k end)
  @access_map Helper.name_to_field_map(@metrics_json, "access",
                transform_fn: &Helper.atomize_access_level_value/1
              )

  @table_map Helper.name_to_field_map(@metrics_json, "table")
  @docs_links_map Helper.name_to_field_map(@metrics_json, "docs_links",
                    required?: false,
                    transform_fn: fn list -> Enum.map(list, fn l -> %{link: l} end) end
                  )

  @aggregation_map Helper.name_to_field_map(@metrics_json, "aggregation",
                     transform_fn: &String.to_atom/1
                   )

  @min_interval_map Helper.name_to_field_map(@metrics_json, "min_interval")
  @min_plan_map Helper.name_to_field_map(@metrics_json, "min_plan",
                  transform_fn: fn plan_map ->
                    Enum.into(plan_map, %{}, fn {k, v} -> {k, String.upcase(v)} end)
                  end
                )

  @human_readable_name_map Helper.name_to_field_map(@metrics_json, "human_readable_name")
  @metric_version_map Helper.name_to_field_map(@metrics_json, "version")
  @metrics_label_map Helper.name_to_field_map(@metrics_json, "label", required?: false)
  @incomplete_data_map Helper.name_to_field_map(@metrics_json, "has_incomplete_data")
  @selectors_map Helper.name_to_field_map(
                   @metrics_json,
                   "selectors",
                   transform_fn: &Enum.map(&1, fn s -> String.to_atom(s) end)
                 )

  @fixed_labels_parameters_metrics_mapset @metrics_json
                                          # The `labels` may change. Come up with a better naming convetion
                                          |> Enum.filter(fn metric ->
                                            metric["fixed_parameters"]["labels"]
                                          end)
                                          |> Enum.map(fn %{"name" => name} -> name end)
                                          |> MapSet.new()

  @fixed_parameters_map Helper.name_to_field_map(@metrics_json, "fixed_parameters",
                          required?: false
                        )

  # The `required_selectors` field contains a list of strings that represent the
  # required selectors for the metric. If one of a few selectors must be present,
  # this is represented in the following way: "label_fqn|label_fqns"
  required_selectors_transform_fn = fn list ->
    Enum.map(list, fn selectors ->
      selectors |> String.split("|") |> Enum.map(&String.to_existing_atom/1)
    end)
  end

  @required_selectors_map Helper.name_to_field_map(
                            @metrics_json,
                            "required_selectors",
                            required?: false,
                            transform_fn: required_selectors_transform_fn
                          )
                          |> Enum.reject(fn {_k, v} -> v == nil end)
                          |> Map.new()

  @deprecated_metrics_map Helper.name_to_field_map(
                            @metrics_json_including_deprecated,
                            "hard_deprecate_after",
                            required?: false,
                            transform_fn: &Sanbase.DateTimeUtils.from_iso8601!/1
                          )
                          |> Enum.reject(fn {_k, v} -> v == nil end)
                          |> Map.new()

  @soft_deprecated_metrics_map Helper.name_to_field_map(
                                 @metrics_json_including_deprecated,
                                 "is_deprecated",
                                 required?: false
                               )
                               |> Enum.reject(fn {_k, v} -> v == nil end)
                               |> Map.new()

  @hidden_metrics_mapset Helper.name_to_field_map(
                           @metrics_json_including_deprecated,
                           "is_hidden",
                           required?: false
                         )
                         |> Enum.filter(fn {_k, v} -> v == true end)
                         |> Enum.map(fn {k, _v} -> k end)
                         |> MapSet.new()

  @metrics_list @metrics_json |> Enum.map(fn %{"name" => name} -> name end)
  @metrics_mapset MapSet.new(@metrics_list)

  @timebound_flag_map @metrics_json
                      |> Map.new(fn metric ->
                        {metric["name"], Map.get(metric, "is_timebound", false)}
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

  def metrics_json(), do: @metrics_json
  def aggregations(), do: @aggregations
  def access_map(), do: @access_map |> transform()
  def table_map(), do: @table_map |> transform()
  def metrics_mapset(), do: @metrics_mapset |> transform()
  def aggregation_map(), do: @aggregation_map |> transform()
  def min_interval_map(), do: @min_interval_map |> transform()
  def min_plan_map(), do: @min_plan_map |> transform()
  def name_to_metric_map(), do: @name_to_metric_map |> transform()
  def docs_links_map(), do: @docs_links_map |> transform()

  def metric_to_names_map(),
    do: @metric_to_names_map |> transform(metric_name_in_map_value_list: true)

  def human_readable_name_map(), do: @human_readable_name_map |> transform()
  def metric_version_map(), do: @metric_version_map |> transform()
  def metrics_data_type_map(), do: @metrics_data_type_map |> transform()
  def incomplete_data_map(), do: @incomplete_data_map |> transform()
  def selectors_map(), do: @selectors_map |> transform()
  def required_selectors_map(), do: @required_selectors_map |> transform()
  def metrics_label_map(), do: @metrics_label_map |> transform()
  def deprecated_metrics_map(), do: @deprecated_metrics_map
  def soft_deprecated_metrics_map(), do: @soft_deprecated_metrics_map
  def hidden_metrics_mapset(), do: @hidden_metrics_mapset |> transform()
  def timebound_flag_map(), do: @timebound_flag_map |> transform()

  def metrics_with_access(level) when level in [:free, :restricted] do
    @access_map
    |> Enum.filter(fn {_metric, restrictions} ->
      Helper.resolve_access_level(restrictions) === level
    end)
    |> Enum.map(&elem(&1, 0))
  end

  def fixed_labels_parameters_metrics_mapset(),
    do: @fixed_labels_parameters_metrics_mapset |> transform()

  def fixed_parameters_map(), do: @fixed_parameters_map |> transform()

  def metrics_with_data_type(type) do
    @metrics_data_type_map
    |> transform()
    |> Enum.filter(fn {_metric, data_type} -> data_type == type end)
    |> Enum.map(&elem(&1, 0))
  end

  def name_to_metric(name), do: Map.get(@name_to_metric_map, name)

  # Private functions

  defp transform(metrics, opts \\ []) do
    # The `remove_hard_deprecated/1` function is used to completely remove
    # hard deprecated metrics. The `deprecated_metrics_map` contains the metric
    # as a key and a datetime as a value. If the current time is after that value,
    # the metric is excluded
    if Keyword.get(opts, :remove_hard_deprecated, true),
      do: remove_hard_deprecated(metrics, opts),
      else: metrics
  end

  defp remove_hard_deprecated(%MapSet{} = metrics, _opts) do
    now = DateTime.utc_now()

    MapSet.reject(metrics, &is_hard_deprecated(&1, now))
  end

  defp remove_hard_deprecated(metrics, _opts) when is_map(metrics) do
    now = DateTime.utc_now()
    Map.reject(metrics, fn {metric, _} -> is_hard_deprecated(metric, now) end)
  end

  defp is_hard_deprecated(metric, now) do
    # Provide `now` as a parameter so it's not calling DateTime.utc_now/0 each time
    # when this is invoked over an enumerable
    hard_deprecate_after = Map.get(@deprecated_metrics_map, metric)

    not is_nil(hard_deprecate_after) and DateTime.compare(hard_deprecate_after, now) == :lt
  end
end
