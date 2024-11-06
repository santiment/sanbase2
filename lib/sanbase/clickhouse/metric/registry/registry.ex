defmodule Sanbase.Clickhouse.MetricAdapter.Registry do
  @moduledoc ~s"""

  """
  require Logger

  import Sanbase.Metric.Registry.EventEmitter, only: [emit_event: 3]

  def access_map(), do: get(:access_map)
  def aggregation_map(), do: get(:aggregation_map)
  def aggregations(), do: get(:aggregations)
  def aggregations_with_nil(), do: get(:aggregations_with_nil)
  def deprecated_metrics_map(), do: get(:deprecated_metrics_map)
  def docs_links_map(), do: get(:docs_links_map)
  def fixed_labels_parameters_metrics_list(), do: get(:fixed_labels_parameters_metrics_list)
  def fixed_labels_parameters_metrics_mapset(), do: get(:fixed_labels_parameters_metrics_mapset)
  def fixed_parameters_map(), do: get(:fixed_parameters_map)
  def hidden_metrics_mapset(), do: get(:hidden_metrics_mapset)
  def human_readable_name_map(), do: get(:human_readable_name_map)
  def incomplete_data_map(), do: get(:incomplete_data_map)
  def incomplete_metrics(), do: get(:incomplete_metrics)
  def metric_to_names_map(), do: get(:metric_to_names_map)
  def metrics_data_type_map(), do: get(:metrics_data_type_map)
  def metrics_list(), do: get(:metrics_list)
  def metrics_list_with_access(level), do: get(:metrics_list_with_access, [level])
  def metrics_list_with_data_type(type), do: get(:metrics_list_with_data_type, [type])
  def metrics_mapset(), do: get(:metrics_mapset)
  def metrics_mapset_with_access(level), do: get(:metrics_mapset_with_access, [level])
  def metrics_mapset_with_data_type(type), do: get(:metrics_mapset_with_data_type, [type])
  def min_interval_map(), do: get(:min_interval_map)
  def min_plan_map(), do: get(:min_plan_map)
  def names_map(), do: get(:names_map)
  def name_to_metric_map(), do: get(:name_to_metric_map)
  def required_selectors_map(), do: get(:required_selectors_map)
  def selectors_map(), do: get(:selectors_map)
  def soft_deprecated_metrics_map(), do: get(:soft_deprecated_metrics_map)
  def table_(), do: get(:table_map)
  def table_map(), do: get(:table_map)
  def timebound_flag_map(), do: get(:timebound_flag_map)

  # Internals below. Some of the functions are public as they are called from
  # other modules, for example when refreshing the stored data in the persistent_term

  @functions [
    {:access_map, []},
    {:aggregation_map, []},
    {:aggregations, []},
    {:aggregations_with_nil, []},
    {:deprecated_metrics_map, []},
    {:docs_links_map, []},
    {:fixed_labels_parameters_metrics_list, []},
    {:fixed_labels_parameters_metrics_mapset, []},
    {:fixed_parameters_map, []},
    {:hidden_metrics_mapset, []},
    {:human_readable_name_map, []},
    {:incomplete_data_map, []},
    {:incomplete_metrics, []},
    {:metric_to_names_map, []},
    {:metrics_data_type_map, []},
    {:metrics_list, []},
    {:metrics_list_with_access, [:free]},
    {:metrics_list_with_access, [:restricted]},
    {:metrics_list_with_data_type, [:histogram]},
    {:metrics_list_with_data_type, [:table]},
    {:metrics_list_with_data_type, [:timeseries]},
    {:metrics_mapset, []},
    {:metrics_mapset_with_access, [:free]},
    {:metrics_mapset_with_access, [:restricted]},
    {:metrics_mapset_with_data_type, [:histogram]},
    {:metrics_mapset_with_data_type, [:table]},
    {:metrics_mapset_with_data_type, [:timeseries]},
    {:min_interval_map, []},
    {:min_plan_map, []},
    {:name_to_metric_map, []},
    {:names_map, []},
    {:required_selectors_map, []},
    {:selectors_map, []},
    {:soft_deprecated_metrics_map, []},
    {:table_map, []},
    {:timebound_flag_map, []}
  ]

  def all_implemented?() do
    not_implemented =
      Enum.filter(@functions, fn {fun, args} ->
        apply(__MODULE__, fun, args) == :not_implemented
      end)

    case not_implemented do
      [] ->
        true

      _ ->
        {:error,
         "The following functions are not implemented: #{Enum.join(not_implemented, ", ")}"}
    end
  end

  def refresh_stored_terms() do
    for {fun, args} <- @functions do
      data = compute(fun, args)

      if :not_implemented == data,
        do: raise("Function #{fun} is not implemented in module #{__MODULE__}")

      :ok = :persistent_term.put(key(fun, args), data)
      {{fun, args}, :ok}
    end
  end

  # Private functions

  defp get_metrics_from_registry(opts) do
    key = {__MODULE__, :get_metrics, opts} |> Sanbase.Cache.hash()

    Sanbase.Cache.get_or_store(key, fn ->
      data =
        Sanbase.Metric.Registry.all()
        |> Sanbase.Metric.Registry.resolve()
        |> filter_exposed_environments(opts)
        |> filter_hard_deprecated(opts)

      {:ok, data}
    end)
  end

  defp filter_exposed_environments(metrics, _opts) do
    deploy_env = Sanbase.Utils.Config.module_get(Sanbase, :deployment_env)

    # the value of exposed_environments can be one of: all, none, stage, prod.
    # the metric is visible if it is "all" or if the env
    # matches the current deploy env of stage or prod.
    # also, in dev mode all metrics are visible, for dev purposes
    Enum.filter(
      metrics,
      fn m ->
        m.exposed_environments in [deploy_env, "all"] or
          deploy_env == "dev"
      end
    )
  end

  defp filter_hard_deprecated(metrics, opts) do
    if Keyword.get(opts, :remove_hard_deprecated, true),
      do: remove_hard_deprecated(metrics),
      else: metrics
  end

  defp get_metrics_from_json(opts) do
    key = {__MODULE__, :get_metrics_from_json, opts} |> Sanbase.Cache.hash()

    Sanbase.Cache.get_or_store(key, fn ->
      data =
        Sanbase.Clickhouse.MetricAdapter.FileHandler.raw_metrics_json()
        |> Enum.map(fn map ->
          changeset = Sanbase.Metric.Registry.Populate.json_map_to_registry_changeset(map)

          if changeset.valid? do
            changeset |> Ecto.Changeset.apply_changes()
          else
            Logger.error("""
            [#{__MODULE__}] JSON map of metric with error: #{map["name"]}
            Error: #{Sanbase.Utils.ErrorHandling.changeset_errors_string(changeset)}
            """)
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Sanbase.Metric.Registry.resolve()
        |> then(fn list ->
          if Keyword.get(opts, :remove_hard_deprecated, true),
            do: remove_hard_deprecated(list),
            else: list
        end)

      {:ok, data}
    end)
  end

  # When trying to fetch the metrics from the DB, several attempts are made
  # After the second attempt, if it still fails, it will start sleeping between
  # 5 milliseconds and 2 seconds. If at the end it still fails, it will get the metrics
  # from the local files.
  @sleep_time_ms %{
    1 => 0,
    2 => 5,
    3 => 10,
    4 => 20,
    5 => 100,
    6 => 500,
    7 => 1000,
    8 => 2000,
    9 => 3000,
    10 => 5000
  }
  @max_attempts 10

  # Try to fetch the metrics from the database table
  # The following options can be passed:
  #   remove_hard_deprecate: boolean() - Remove the hard deprecated metrics who  have
  #     hard_deprecate_after set to a date in the past
  #   from: The name of the function that called this function. This can be used in logs
  #     for debug purposes
  defp get_metrics(opts, attempt \\ 1) do
    case get_metrics_from_registry(opts) do
      {:ok, data} ->
        data

      {:error, _} when attempt <= @max_attempts ->
        Process.sleep(@sleep_time_ms[attempt])
        get_metrics(opts, attempt + 1)

      {:error, _error} ->
        emit_event(:ok, :metric_registry_failed_to_load, %{})
        {:ok, data} = get_metrics_from_json(opts)
        data
    end
  end

  # Get the data from the persistent_term that is stored under `key`
  # If the record does not exist, invoke `compute(key)` to compute it,
  # store the data in persistent_term and then return it.
  # The arguments are:
  #   func -- the name of the function
  #   args -- the arguments that will be passed to compute.
  # The arguments are all packed in a single list so `compute/2` can be always a function
  # of 2 arguments. This makes it more easy to automatically refresh the values
  # using the refresh_stored_terms/0 function
  defp get(fun, args \\ []) when is_atom(fun) and is_list(args) do
    key = key(fun, args)

    case :persistent_term.get(key, :undefined) do
      :undefined ->
        data = compute(fun, args)
        :persistent_term.put(key, data)
        data

      data ->
        data
    end
  end

  defp key(fun, args) when is_atom(fun) and is_list(args),
    do: {__MODULE__, fun, args}

  defp compute(:aggregations, []), do: Sanbase.Metric.SqlQuery.Helper.aggregations()

  defp compute(:aggregations_with_nil, []), do: [nil] ++ aggregations()

  defp compute(:access_map, []) do
    get_metrics(from: __ENV__.function)
    |> Map.new(&{&1.metric, String.to_existing_atom(&1.access)})
  end

  defp compute(:table_map, []) do
    get_metrics(from: __ENV__.function)
    |> Map.new(fn map ->
      # Almost all metrics have a single source table.
      # The exceptions are custom metrics that are handled in a custom way,
      # so for them there will be no "FROM #{Map.get(Registry.table_map(), metric)}" code
      # so it is safe to unpack the list in case of single table
      table_or_tables =
        case map.table do
          [table] -> table
          [_ | _] = tables -> tables
        end

      {map.metric, table_or_tables}
    end)
  end

  defp compute(:metrics_list, []),
    do: get_metrics(from: __ENV__.function) |> Enum.map(& &1.metric)

  defp compute(:metrics_mapset, []),
    do: get_metrics(from: __ENV__.function) |> MapSet.new(& &1.metric)

  defp compute(:aggregation_map, []) do
    get_metrics(from: __ENV__.function)
    |> Map.new(&{&1.metric, String.to_existing_atom(&1.aggregation)})
  end

  defp compute(:min_interval_map, []) do
    get_metrics(from: __ENV__.function) |> Map.new(&{&1.metric, &1.min_interval})
  end

  defp compute(:min_plan_map, []) do
    get_metrics(from: __ENV__.function)
    |> Map.new(fn metric_map ->
      min_plan =
        case metric_map.min_plan do
          %{} = map -> Map.new(map, fn {k, v} -> {String.upcase(k), String.upcase(v)} end)
          plan when is_binary(plan) -> String.upcase(plan)
        end

      {metric_map.metric, min_plan}
    end)
  end

  defp compute(:names_map, []) do
    get_metrics(from: :names_map) |> Map.new(&{&1.metric, &1.internal_metric})
  end

  defp compute(:docs_links_map, []) do
    get_metrics(from: :docs_links_map) |> Map.new(&{&1.metric, &1.docs_links})
  end

  defp compute(:name_to_metric_map, []) do
    get_metrics(from: :name_to_metric_map) |> Map.new(&{&1.metric, &1.internal_metric})
  end

  defp compute(:metric_to_names_map, []) do
    get_metrics(from: :metric_to_names_map)
    |> Enum.group_by(& &1.internal_metric, & &1.metric)
  end

  defp compute(:human_readable_name_map, []) do
    get_metrics(from: :human_readable_name_map) |> Map.new(&{&1.metric, &1.human_readable_name})
  end

  defp compute(:metrics_data_type_map, []) do
    get_metrics(from: :metrics_data_type_map)
    |> Map.new(&{&1.metric, String.to_atom(&1.data_type)})
  end

  defp compute(:incomplete_data_map, []) do
    get_metrics(from: :incomplete_data_map) |> Map.new(&{&1.metric, &1.has_incomplete_data})
  end

  defp compute(:incomplete_metrics, []) do
    get_metrics(from: :incomplete_metrics)
    |> Enum.filter(& &1.has_incomplete_data)
    |> Enum.map(& &1.metric)
  end

  defp compute(:selectors_map, []) do
    get_metrics(from: :selectors_map)
    |> Map.new(fn m ->
      selectors = Enum.map(m.selectors, &String.to_atom/1)
      {m.metric, selectors}
    end)
  end

  defp compute(:required_selectors_map, []) do
    get_metrics(from: :required_selectors_map)
    |> Enum.reject(&(&1.required_selectors == []))
    |> Map.new(fn m ->
      # ["slug", "label_fqn|label_fqns"] should be parsed as [:slug, [:label_fqn, :label_fqns]]
      # When the element is a list itself, it means that one of the elements must be present.
      # In the above example, when querying the metric the user must provide slug and label_fqn or
      # slug and label_fqns
      required_selectors =
        Enum.map(m.required_selectors, fn binary_selectors ->
          binary_selectors |> String.split("|") |> Enum.map(&String.to_atom/1)
        end)

      {m.metric, required_selectors}
    end)
  end

  defp compute(:deprecated_metrics_map, []) do
    get_metrics(from: :deprecated_metrics_map, remove_hard_deprecated: false)
    |> Enum.filter(& &1.hard_deprecate_after)
    |> Map.new(&{&1.metric, &1.hard_deprecate_after})
  end

  defp compute(:soft_deprecated_metrics_map, []) do
    get_metrics(from: :soft_deprecated_metrics_map)
    |> Map.new(&{&1.metric, &1.is_deprecated})
  end

  defp compute(:hidden_metrics_mapset, []) do
    get_metrics(from: :hidden_metrics_mapset)
    |> Enum.filter(& &1.is_hidden)
    |> MapSet.new(& &1.metric)
  end

  defp compute(:timebound_flag_map, []) do
    get_metrics(from: :timebound_flag_map)
    |> Map.new(&{&1.metric, &1.is_timebound})
  end

  defp compute(:metrics_list_with_access, [level]) when level in [:free, :restricted] do
    access_map()
    |> Enum.reduce([], fn {metric, restrictions}, acc ->
      if resolve_access_level(restrictions) === level,
        do: [metric | acc],
        else: acc
    end)
  end

  defp compute(:metrics_mapset_with_access, [level]) when level in [:free, :restricted] do
    access_map()
    |> Enum.reduce(MapSet.new(), fn {metric, restrictions}, acc ->
      if resolve_access_level(restrictions) === level,
        do: MapSet.put(acc, metric),
        else: acc
    end)
  end

  defp compute(:fixed_labels_parameters_metrics_mapset, []) do
    get_metrics(from: :fixed_labels_parameters_metrics_mapset)
    |> Enum.reduce(MapSet.new(), fn m, acc ->
      case m.fixed_parameters do
        %{} = map when map_size(map) == 0 -> acc
        %{} = map when map_size(map) > 0 -> MapSet.put(acc, m.metric)
      end
    end)
  end

  defp compute(:fixed_labels_parameters_metrics_list, []) do
    Enum.to_list(fixed_labels_parameters_metrics_mapset())
  end

  defp compute(:fixed_parameters_map, []) do
    get_metrics(from: :fixed_parameters_map)
    |> Map.new(&{&1.metric, &1.fixed_parameters})
  end

  defp compute(:metrics_list_with_data_type, [type]) do
    get_metrics(from: {:metrics_list_with_data_type, type})
    |> Enum.reduce([], fn m, acc ->
      if String.to_atom(m.data_type) == type,
        do: [m.metric | acc],
        else: acc
    end)
  end

  defp compute(:metrics_mapset_with_data_type, [type]) do
    get_metrics(from: {:metrics_mapset_with_data_type, type})
    |> Enum.reduce(MapSet.new(), fn m, acc ->
      if String.to_atom(m.data_type) == type,
        do: MapSet.put(acc, m.metric),
        else: acc
    end)
  end

  defp compute(_fun, _args), do: :not_implemented

  defp remove_hard_deprecated(metrics) when is_list(metrics) do
    now = DateTime.utc_now()
    Enum.reject(metrics, fn map -> is_hard_deprecated(map, now) end)
  end

  defp is_hard_deprecated(map, now) do
    hard_deprecate_after = Map.get(map, :hard_deprecate_after, nil)

    not is_nil(hard_deprecate_after) and DateTime.compare(hard_deprecate_after, now) == :lt
  end

  defp resolve_access_level(access) when is_atom(access), do: access

  defp resolve_access_level(access) when is_map(access) do
    case access do
      %{"historical" => :free, "realtime" => :free} -> :free
      _ -> :restricted
    end
  end
end
