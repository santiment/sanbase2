defmodule Sanbase.Clickhouse.MetricAdapter.Registry do
  @moduledoc ~s"""
  TODO
  """
  import Sanbase.Metric.Registry.EventEmitter, only: [emit_event: 3]
  require Logger

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
  def can_mutate_map(), do: get(:can_mutate_map)
  def stabilization_period_map(), do: get(:stabilization_period_map)
  def name_to_metric_map(), do: get(:name_to_metric_map)
  def name_to_status_map(), do: get(:name_to_status_map)
  def registry_id_map(), do: get(:registry_id_map)
  def required_selectors_map(), do: get(:required_selectors_map)
  def selectors_map(), do: get(:selectors_map)
  def soft_deprecated_metrics_map(), do: get(:soft_deprecated_metrics_map)
  def table_map(), do: get(:table_map)
  def timebound_flag_map(), do: get(:timebound_flag_map)

  # Internals below. Some are public because other modules call them, for example when
  # refreshing the data stored in the persistent_term.

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
    {:name_to_status_map, []},
    {:registry_id_map, []},
    {:can_mutate_map, []},
    {:stabilization_period_map, []},
    {:names_map, []},
    {:required_selectors_map, []},
    {:selectors_map, []},
    {:soft_deprecated_metrics_map, []},
    {:table_map, []},
    {:timebound_flag_map, []}
  ]

  def by_name(name) do
    get_metrics([])
    |> Enum.find(fn metric -> metric.metric == name end)
  end

  def metrics_by_status(status) do
    get_metrics([])
    |> Enum.filter(&(&1.status == status))
    |> MapSet.new(& &1.metric)
  end

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
    Logger.info("Refreshing stored terms in the #{__MODULE__} module")
    # Clear the registry cache first, or the changes that triggered this refresh are not
    # re-fetched from the DB.
    Sanbase.Cache.clear(registry_cache_key([]))
    Sanbase.Cache.clear(registry_cache_key(remove_hard_deprecated: true))
    Sanbase.Cache.clear(registry_cache_key(remove_hard_deprecated: false))

    result =
      for {fun, args} <- @functions do
        data = compute(fun, args)

        if :not_implemented == data,
          do: raise("Function #{fun} is not implemented in module #{__MODULE__}")

        result = :persistent_term.put(key(fun, args), data)
        {{fun, args}, result}
      end

    Enum.all?(result, &match?({_, :ok}, &1))
  end

  # Private functions

  defp registry_cache_key(opts) do
    {__MODULE__, :get_metrics_from_registry, opts} |> Sanbase.Cache.hash()
  end

  defp get_metrics_from_registry(opts) do
    # No other keys allowed - every possible cache must be invalidated on refresh.
    Keyword.validate!(opts, [:remove_hard_deprecated])

    Sanbase.Cache.get_or_store(registry_cache_key(opts), fn ->
      # TODO: Show somewhere that the registries with errors.
      {data, _registires_with_errors} =
        Sanbase.Metric.Registry.all()
        |> Sanbase.Metric.Registry.resolve_safe()

      data =
        data
        |> filter_exposed_environments(opts)
        |> filter_hard_deprecated(opts)

      {:ok, data}
    end)
  end

  defp filter_exposed_environments(metrics, _opts) do
    deploy_env = Sanbase.Utils.Config.module_get(Sanbase, :deployment_env)

    # exposed_environments is all/none/stage/prod: visible when "all" or when it matches
    # the deploy env. In dev everything is visible.
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
        |> Sanbase.Metric.Registry.resolve_safe()
        |> then(fn {list, _registries_with_errors} ->
          if Keyword.get(opts, :remove_hard_deprecated, true),
            do: remove_hard_deprecated(list),
            else: list
        end)

      {:ok, data}
    end)
  end

  # Retried a few times, sleeping 5ms to 2s from the second attempt on. If every attempt
  # fails, the local files are used.
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

  # Fetch the metrics from the database table. Options:
  #   remove_hard_deprecate: boolean() - drop metrics whose hard_deprecate_after is in the
  #     past
  #   from: the name of the calling function, used in logs for debugging
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

  # The data in persistent_term under `key`, computed with `compute(key)` and stored first
  # if missing. Packing `fun` and `args` in one list keeps `compute/2` two-argument, which
  # is what lets refresh_stored_terms/0 refresh everything automatically.
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

  # NOTE: compute/2 must NEVER call a public function reading from the persistent_term -
  # that interferes with the refresh and leaves the data stale.
  defp compute(:aggregations, []), do: Sanbase.Metric.SqlQuery.Helper.aggregations()

  defp compute(:aggregations_with_nil, []), do: [nil] ++ aggregations()

  defp compute(:access_map, []) do
    get_metrics([])
    |> Map.new(&{&1.metric, String.to_existing_atom(&1.access)})
  end

  defp compute(:table_map, []) do
    get_metrics([])
    |> Map.new(fn map ->
      # Almost all metrics have a single source table; the exceptions are custom metrics
      # emitting no "FROM ...", so unpacking the single-table list is safe.
      table_or_tables =
        case map.tables do
          [table] -> table.name
          [_ | _] = tables -> Enum.map(tables, & &1.name)
        end

      {map.metric, table_or_tables}
    end)
  end

  defp compute(:metrics_list, []),
    do: get_metrics([]) |> Enum.map(& &1.metric)

  defp compute(:metrics_mapset, []),
    do: get_metrics([]) |> MapSet.new(& &1.metric)

  defp compute(:aggregation_map, []) do
    get_metrics([])
    |> Map.new(&{&1.metric, String.to_existing_atom(&1.default_aggregation)})
  end

  defp compute(:min_interval_map, []) do
    get_metrics([]) |> Map.new(&{&1.metric, &1.min_interval})
  end

  defp compute(:min_plan_map, []) do
    get_metrics([])
    |> Map.new(fn metric_map ->
      min_plan_map = %{
        "SANBASE" => String.upcase(metric_map.sanbase_min_plan),
        "SANAPI" => String.upcase(metric_map.sanapi_min_plan)
      }

      {metric_map.metric, min_plan_map}
    end)
  end

  defp compute(:names_map, []) do
    get_metrics([]) |> Map.new(&{&1.metric, &1.internal_metric})
  end

  defp compute(:docs_links_map, []) do
    get_metrics([]) |> Map.new(fn m -> {m.metric, m.docs} end)
  end

  defp compute(:name_to_metric_map, []) do
    get_metrics([]) |> Map.new(&{&1.metric, &1.internal_metric})
  end

  defp compute(:name_to_status_map, []) do
    get_metrics([]) |> Map.new(&{&1.metric, &1.status})
  end

  # Maps every resolved metric name to the id of the metric registry record it
  # comes from. Template metrics and aliases all point to their parent record,
  # which is what the category mappings reference.
  defp compute(:registry_id_map, []) do
    get_metrics([])
    |> Enum.reject(&is_nil(&1.id))
    |> Map.new(&{&1.metric, &1.id})
  end

  defp compute(:metric_to_names_map, []) do
    get_metrics([])
    |> Enum.group_by(& &1.internal_metric, & &1.metric)
  end

  defp compute(:human_readable_name_map, []) do
    get_metrics([]) |> Map.new(&{&1.metric, &1.human_readable_name})
  end

  defp compute(:metrics_data_type_map, []) do
    get_metrics([])
    # credo:disable-for-next-line
    |> Map.new(&{&1.metric, String.to_atom(&1.data_type)})
  end

  defp compute(:incomplete_data_map, []) do
    get_metrics([]) |> Map.new(&{&1.metric, &1.has_incomplete_data})
  end

  defp compute(:stabilization_period_map, []) do
    get_metrics([]) |> Map.new(&{&1.metric, &1.stabilization_period})
  end

  defp compute(:can_mutate_map, []) do
    get_metrics([]) |> Map.new(&{&1.metric, &1.can_mutate})
  end

  defp compute(:incomplete_metrics, []) do
    get_metrics([])
    |> Enum.filter(& &1.has_incomplete_data)
    |> Enum.map(& &1.metric)
  end

  defp compute(:selectors_map, []) do
    get_metrics([])
    |> Map.new(fn m ->
      selectors =
        m.selectors
        |> Enum.map(& &1.type)
        # credo:disable-for-next-line
        |> Enum.map(&String.to_atom/1)

      {m.metric, selectors}
    end)
  end

  defp compute(:required_selectors_map, []) do
    get_metrics([])
    |> Enum.reject(&(&1.required_selectors == []))
    |> Map.new(fn m ->
      # ["slug", "label_fqn|label_fqns"] parses as [:slug, [:label_fqn, :label_fqns]]: a
      # nested list means one of its elements must be present.
      required_selectors =
        m.required_selectors
        |> Enum.map(& &1.type)
        |> Enum.map(fn binary_selectors ->
          # credo:disable-for-next-line
          binary_selectors |> String.split("|") |> Enum.map(&String.to_atom/1)
        end)

      {m.metric, required_selectors}
    end)
  end

  defp compute(:deprecated_metrics_map, []) do
    get_metrics(remove_hard_deprecated: false)
    |> Enum.filter(& &1.hard_deprecate_after)
    |> Map.new(&{&1.metric, &1.hard_deprecate_after})
  end

  defp compute(:soft_deprecated_metrics_map, []) do
    get_metrics([])
    |> Map.new(&{&1.metric, &1.is_deprecated})
  end

  defp compute(:hidden_metrics_mapset, []) do
    get_metrics([])
    |> Enum.filter(& &1.is_hidden)
    |> MapSet.new(& &1.metric)
  end

  defp compute(:timebound_flag_map, []) do
    get_metrics([])
    |> Map.new(&{&1.metric, &1.is_timebound})
  end

  defp compute(:metrics_list_with_access, [level]) when level in [:free, :restricted] do
    compute(:access_map, [])
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
    get_metrics([])
    |> Enum.reduce(MapSet.new(), fn m, acc ->
      case m.fixed_parameters do
        %{} = map when map_size(map) == 0 -> acc
        %{} = map when map_size(map) > 0 -> MapSet.put(acc, m.metric)
      end
    end)
  end

  defp compute(:fixed_labels_parameters_metrics_list, []) do
    compute(:fixed_labels_parameters_metrics_mapset, [])
    |> Enum.to_list()
  end

  defp compute(:fixed_parameters_map, []) do
    get_metrics([])
    |> Map.new(&{&1.metric, &1.fixed_parameters})
  end

  defp compute(:metrics_list_with_data_type, [type]) do
    get_metrics([])
    |> Enum.reduce([], fn m, acc ->
      # credo:disable-for-next-line
      if String.to_atom(m.data_type) == type,
        do: [m.metric | acc],
        else: acc
    end)
  end

  defp compute(:metrics_mapset_with_data_type, [type]) do
    get_metrics([])
    |> Enum.reduce(MapSet.new(), fn m, acc ->
      # credo:disable-for-next-line
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
