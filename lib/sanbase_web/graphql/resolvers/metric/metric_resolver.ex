defmodule SanbaseWeb.Graphql.Resolvers.MetricResolver do
  import SanbaseWeb.Graphql.Helpers.Utils
  import SanbaseWeb.Graphql.Helpers.CalibrateInterval

  import Sanbase.Utils.ErrorHandling,
    only: [handle_graphql_error: 3, maybe_handle_graphql_error: 2]

  import Sanbase.Project.Selector,
    only: [args_to_selector: 2, args_to_raw_selector: 1]

  import SanbaseWeb.Graphql.Helpers.Utils

  alias Sanbase.Metric
  alias Sanbase.Billing.Plan.Restrictions
  alias Sanbase.Billing.Plan.AccessChecker
  alias SanbaseWeb.Graphql.Resolvers.MetricTransform

  require Logger

  @datapoints 300

  @wordsize 8
  @max_heap_size_in_mbs 500
  @max_heap_size_in_words div(@max_heap_size_in_mbs * 1024 * 1024, @wordsize)

  def get_metric(_root, %{metric: metric} = args, _resolution) do
    with false <- Metric.hard_deprecated?(metric),
         true <- Metric.has_metric?(metric) do
      maybe_enable_clickhouse_sql_storage(args)
      {:ok, %{metric: metric}}
    end
  end

  # If the `store_executed_clickhouse_sql` flag is true, put a value
  # in the process dictionary that will indicate to the ClickhouseRepo
  # module that the executed queries need to be stored in the process
  # dictionary.
  defp maybe_enable_clickhouse_sql_storage(args) do
    if Map.get(args, :store_executed_clickhouse_sql, false),
      do: Process.put(:__store_executed_clickhouse_sql__, true)
  end

  # Return the list of executed Clickhouse SQL queries.
  # The list is not empty if `store_executed_clickhouse_sql` flag is true
  # and there are executed SQL queries. If the flag is set to false or there were
  # no SQL queries executed because (not requested or served from cache)
  def get_executed_clickhouse_sql(_root, _args, _resolution) do
    {:ok, Process.get(:__executed_clickhouse_sql_list__, []) |> Enum.reverse()}
  end

  def get_available_metrics(_root, %{plan: plan, product: product} = args, resolution) do
    product_code = product |> Atom.to_string() |> String.upcase()
    plan_name = plan |> to_string() |> String.upcase()

    user_metric_access_level =
      get_in(resolution.context, [:auth, :current_user, Access.key(:metric_access_level)]) ||
        "released"

    metrics =
      AccessChecker.get_available_metrics_for_plan(plan_name, product_code)
      |> maybe_filter_incomplete_metrics(args[:has_incomplete_data])
      |> maybe_apply_regex_filter(args[:name_regex_filter])
      |> remove_hidden_metrics()
      |> maybe_remove_experimental_metrics(user_metric_access_level)
      |> Enum.uniq()
      |> Enum.sort(:asc)

    {:ok, metrics}
  end

  def get_available_metrics(_root, args, resolution) do
    user_metric_access_level =
      get_in(resolution.context, [:auth, :current_user, Access.key(:metric_access_level)]) ||
        "released"

    metrics =
      Metric.available_metrics()
      |> maybe_filter_incomplete_metrics(args[:has_incomplete_data])
      |> maybe_apply_regex_filter(args[:name_regex_filter])
      |> remove_hidden_metrics()
      |> maybe_remove_experimental_metrics(user_metric_access_level)
      |> Enum.uniq()
      |> Enum.sort(:asc)

    {:ok, metrics}
  end

  def get_available_metrics_for_selector(_root, args, resolution) do
    user_metric_access_level =
      get_in(resolution.context, [:auth, :current_user, Access.key(:metric_access_level)]) ||
        "released"

    case Metric.available_metrics_for_selector(args.selector,
           user_metric_access_level: user_metric_access_level
         ) do
      {:ok, metrics} ->
        metrics = maybe_apply_regex_filter(metrics, args[:name_regex_filter])
        metrics = Enum.sort(metrics, :asc)

        {:ok, metrics}

      {:nocache, {:ok, metrics}} ->
        metrics = maybe_apply_regex_filter(metrics, args[:name_regex_filter])
        metrics = metrics |> Enum.uniq() |> Enum.sort(:asc)

        {:nocache, {:ok, metrics}}
    end
  end

  def get_available_slugs(_root, _args, %{source: %{metric: metric}}),
    do: Metric.available_slugs(metric)

  def get_available_projects(_root, _args, %{source: %{metric: metric}}) do
    with {:ok, slugs} <- Metric.available_slugs(metric) do
      slugs = Enum.sort(slugs, :asc)
      {:ok, Sanbase.Project.List.by_slugs(slugs)}
    end
  end

  def get_available_label_fqns(_root, args, %{source: %{metric: metric}}) do
    case args[:slug] do
      nil -> Metric.available_label_fqns(metric)
      slug when is_binary(slug) -> Metric.available_label_fqns(metric, %{slug: slug})
    end
  end

  def get_available_founders(_root, args, %{source: %{metric: metric}}) do
    with {:ok, selectors} <- Metric.available_selectors(metric) do
      case :founders in selectors do
        true ->
          slug = Map.get(args, :slug, nil)

          with {:ok, data} <- Sanbase.Clickhouse.Founders.get_founders(slug) do
            slugs = Enum.map(data, & &1.slug)
            projects = Sanbase.Project.List.by_slugs(slugs)
            slug_to_project_map = Map.new(projects, &{&1.slug, &1})

            result =
              Enum.map(data, fn map ->
                Map.put(map, :project, slug_to_project_map[map.slug])
              end)

            {:ok, result}
          end

        false ->
          {:ok, []}
      end
    end
  end

  def get_human_readable_name(_root, _args, %{source: %{metric: metric}}),
    do: Metric.human_readable_name(metric)

  def get_metadata(%{}, _args, %{source: %{metric: metric}} = resolution) do
    %{
      context: %{
        requested_product: requested_product,
        subscription_product: subcription_product,
        auth: %{plan: plan_name}
      }
    } = resolution

    case Metric.metadata(metric) do
      {:ok, metadata} ->
        access_restrictions =
          Restrictions.get({:metric, metric}, requested_product, subcription_product, plan_name)

        {:ok, Map.merge(access_restrictions, metadata)}

      {:error, error} ->
        {:error, handle_graphql_error("metadata", %{metric: metric}, error)}
    end
  end

  def get_available_selectors(_root, _args, %{source: %{metric: metric}}) do
    case Metric.available_selectors(metric) do
      {:ok, selectors} ->
        {:ok, selectors}

      {:error, error} ->
        {:error, handle_graphql_error("available_selectors", %{metric: metric}, error)}
    end
  end

  def timeseries_data_complexity(_root, args, resolution) do
    # Explicitly set `child_complexity` to 2 as this would be the
    # value if both `datetime` and `value` fields are queried.
    child_complexity = 2

    complexity =
      SanbaseWeb.Graphql.Complexity.from_to_interval(args, child_complexity, resolution)
      |> Sanbase.Math.to_integer()

    {:ok, complexity}
  end

  def available_since(_root, args, %{source: %{metric: metric}}) do
    with {:ok, selector} <- args_to_selector(args, use_process_dictionary: true),
         true <- all_required_selectors_present?(metric, selector),
         {:ok, opts} <- selector_args_to_opts(args),
         {:ok, first_datetime} <- Metric.first_datetime(metric, selector, opts) do
      {:ok, first_datetime}
    end
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(
        "Available Since",
        %{metric: metric, selector: args_to_raw_selector(args)},
        error
      )
    end)
  end

  def last_datetime_computed_at(_root, args, %{source: %{metric: metric}}) do
    with {:ok, selector} <- args_to_selector(args, use_process_dictionary: true),
         true <- all_required_selectors_present?(metric, selector),
         {:ok, opts} <- selector_args_to_opts(args),
         true <- valid_metric_selector_pair?(metric, selector) do
      Metric.last_datetime_computed_at(metric, selector, opts)
    end
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(
        "Last Datetime Computed At",
        %{metric: metric, selector: args_to_raw_selector(args)},
        error
      )
    end)
  end

  def broken_data(_root, %{from: from, to: to} = args, %{source: %{metric: metric}}) do
    with {:ok, selector} <- args_to_selector(args, use_process_dictionary: true),
         true <- all_required_selectors_present?(metric, selector),
         true <- valid_metric_selector_pair?(metric, selector),
         true <- valid_owners_labels_selection?(args),
         {:ok, result} <- Metric.broken_data(metric, selector, from, to) do
      {:ok, result}
    end
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(metric, args_to_raw_selector(args), error)
    end)
  end

  def timeseries_data(_root, args, %{source: %{metric: metric}} = resolution) do
    requested_fields = requested_fields(resolution)
    fetch_timeseries_data(metric, args, requested_fields, :timeseries_data)
  rescue
    e in [Sanbase.Metric.CatchableError] -> {:error, Exception.message(e)}
    e -> reraise(e, __STACKTRACE__)
  end

  def timeseries_data_per_slug(
        _root,
        args,
        %{source: %{metric: metric}} = resolution
      ) do
    Process.flag(:max_heap_size, @max_heap_size_in_words)
    requested_fields = requested_fields(resolution)

    fetch_timeseries_data(
      metric,
      args,
      requested_fields,
      :timeseries_data_per_slug
    )
  rescue
    e in [Sanbase.Metric.CatchableError] -> {:error, Exception.message(e)}
    e -> reraise(e, __STACKTRACE__)
  end

  def aggregated_timeseries_data(
        _root,
        %{from: from, to: to} = args,
        %{source: %{metric: metric}}
      ) do
    include_incomplete_data = Map.get(args, :include_incomplete_data, false)
    only_finalized_data = Map.get(args, :only_finalized_data, false)

    with {:ok, selector} <- args_to_selector(args, use_process_dictionary: true),
         true <- all_required_selectors_present?(metric, selector),
         true <- valid_metric_selector_pair?(metric, selector),
         true <- valid_owners_labels_selection?(args),
         {:ok, opts} <- selector_args_to_opts(args),
         opts <- Keyword.put(opts, :only_finalized_data, only_finalized_data),
         {:ok, from, to} <-
           calibrate_incomplete_data_params(
             include_incomplete_data,
             Metric,
             metric,
             from,
             to
           ),
         {:ok, result} <-
           Metric.aggregated_timeseries_data(metric, selector, from, to, opts) do
      {:ok, Map.values(result) |> List.first()}
    end
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(metric, args_to_raw_selector(args), error)
    end)
  rescue
    e in [Sanbase.Metric.CatchableError] -> {:error, Exception.message(e)}
    e -> reraise(e, __STACKTRACE__)
  end

  def histogram_data(
        _root,
        args,
        %{source: %{metric: metric}}
      ) do
    %{to: to, interval: interval, limit: limit} = args

    # from datetime arg is not required for `all_spent_coins_cost` metric which calculates
    # the histogram for all time.
    from = Map.get(args, :from, nil)
    interval = transform_interval(metric, interval)

    with true <- valid_histogram_args?(metric, args),
         {:ok, selector} <- args_to_selector(args, use_process_dictionary: true),
         true <- all_required_selectors_present?(metric, selector),
         true <- valid_metric_selector_pair?(metric, selector),
         true <- valid_owners_labels_selection?(args),
         {:ok, data} <-
           Metric.histogram_data(metric, selector, from, to, interval, limit),
         {:ok, data} <- maybe_enrich_with_labels(metric, data) do
      {:ok, %{values: %{data: data}}}
    end
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(metric, args_to_raw_selector(args), error)
    end)
  end

  def table_data(
        _root,
        %{from: from, to: to} = args,
        %{source: %{metric: metric}}
      ) do
    with {:ok, selector} <- args_to_selector(args, use_process_dictionary: true),
         true <- all_required_selectors_present?(metric, selector),
         true <- valid_metric_selector_pair?(metric, selector),
         true <- valid_owners_labels_selection?(args),
         {:ok, data} <- Metric.table_data(metric, selector, from, to) do
      {:ok, data}
    end
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(metric, args_to_raw_selector(args), error)
    end)
  end

  def latest_metrics_data(_root, %{metrics: metrics} = args, _resolution) do
    with {:ok, selector} <- args_to_selector(args, use_process_dictionary: true),
         :ok <- check_metrics_slugs_cartesian_limit(metrics, selector, 20_000),
         {:ok, data} <-
           Metric.LatestMetric.latest_metrics_data(metrics, selector) do
      {:ok, data}
    end
  end

  # Private functions

  # required_selectors is a list of lists like [["slug"], ["label_fqn", "label_fqns"]]
  # At least one of the elements in every list must be present. A list of length
  # greater than 1 is used mostly with singlure/plural versions of the same thing.
  defp all_required_selectors_present?(metric, selector) do
    selector_names = Map.keys(selector)

    with {:ok, required_selectors} <- Metric.required_selectors(metric),
         true <-
           do_check_required_selectors(
             metric,
             selector_names,
             required_selectors
           ) do
      true
    end
  end

  defp do_check_required_selectors(metric, selector_names, required_selectors) do
    required_selectors
    |> Enum.reduce_while(true, fn list, acc ->
      case Enum.any?(list, &(&1 in selector_names)) do
        true ->
          {:cont, acc}

        false ->
          selectors_str =
            list
            |> Enum.map(&Atom.to_string/1)
            |> Enum.map(&Inflex.camelize(&1, :lower))
            |> Enum.join(", ")

          {:halt,
           {:error,
            "The metric '#{metric}' must have at least one of the following fields in the selector: #{selectors_str}"}}
      end
    end)
  end

  # This is used when a list of slugs and a list of metrics is provided
  # Every metric is fetched for every slug and the result length can get too big
  defp check_metrics_slugs_cartesian_limit(
         metrics,
         %{slug: slug_or_slugs},
         limit
       ) do
    slugs = List.wrap(slug_or_slugs)
    cartesian_product_length = length(metrics) * length(slugs)

    case cartesian_product_length <= limit do
      true -> :ok
      false -> {:error, "The length of the metrics multiplied by the length of\
      the slugs must not exceed #{limit}."}
    end
  end

  # timeseries_data and timeseries_data_per_slug are processed and fetched in
  # exactly the same way. The only difference is the function that is called
  # from the Metric module.
  defp fetch_timeseries_data(metric, args, requested_fields, function)
       when function in [:timeseries_data, :timeseries_data_per_slug] do
    only_finalized_data = Map.get(args, :only_finalized_data, false)

    with {:ok, selector} <- args_to_selector(args, use_process_dictionary: true),
         {:ok, transform} <- MetricTransform.args_to_transform(args),
         true <- all_required_selectors_present?(metric, selector),
         true <- valid_metric_selector_pair?(metric, selector),
         true <- valid_owners_labels_selection?(args),
         true <- valid_timeseries_selection?(requested_fields, args),
         {:ok, opts} <- selector_args_to_opts(args),
         opts <- Keyword.put(opts, :only_finalized_data, only_finalized_data),
         {:ok, from, to, interval} <-
           transform_datetime_params(selector, metric, transform, args),
         {:ok, result} <-
           apply(Metric, function, [metric, selector, from, to, interval, opts]),
         {:ok, result} <- MetricTransform.apply_transform(transform, result),
         {:ok, result} <- fit_from_datetime(result, %{args | interval: interval}),
         {:ok, result} <- maybe_rename_fields(result, function, args) do
      result = result |> Enum.reject(&is_nil/1)
      {:ok, result}
    end
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(metric, args_to_raw_selector(args), error)
    end)
  end

  defp maybe_rename_fields(result, :timeseries_data, %{fields: map})
       when is_map(map) and map_size(map) > 0 do
    result =
      result
      |> Enum.map(fn
        %{datetime: d, value: v} ->
          %{
            Map.get(map, :datetime, :datetime) => d,
            Map.get(map, :value, :value) => v
          }

        %{datetime: d, value_ohlc: ohlc} ->
          %{
            Map.get(map, :datetime, :datetime) => d,
            Map.get(map, :value_ohlc, :value_ohlc) => %{
              Map.get(map, :open, :open) => ohlc.open,
              Map.get(map, :high, :high) => ohlc.high,
              Map.get(map, :close, :close) => ohlc.close,
              Map.get(map, :low, :low) => ohlc.low
            }
          }
      end)

    {:ok, result}
  end

  defp maybe_rename_fields(result, :timeseries_data_per_slug, %{fields: map})
       when is_map(map) and map_size(map) > 0 do
    result =
      result
      |> Enum.map(fn %{datetime: datetime, data: data} ->
        %{
          Map.get(map, :datetime, :datetime) => datetime,
          Map.get(map, :data, :data) =>
            Enum.map(data, fn
              %{value: value, slug: slug} ->
                %{
                  Map.get(map, :value, :value) => value,
                  Map.get(map, :slug, :slug) => slug
                }
            end)
        }
      end)

    {:ok, result}
  end

  defp maybe_rename_fields(result, _function, _args), do: {:ok, result}

  defp transform_datetime_params(selector, metric, transform, args) do
    %{from: from, to: to, interval: interval} = args

    include_incomplete_data = Map.get(args, :include_incomplete_data, false)

    with {:ok, interval} <- interval_no_smaller_than_min_interval(metric, interval),
         {:ok, from, to, interval} <-
           calibrate(Metric, metric, selector, from, to, interval, 86_400, @datapoints),
         {:ok, from, to} <-
           calibrate_incomplete_data_params(include_incomplete_data, Metric, metric, from, to),
         {:ok, from} <-
           MetricTransform.calibrate_transform_params(transform, from, to, interval) do
      {:ok, from, to, interval}
    end
  end

  defp interval_no_smaller_than_min_interval(metric, interval) do
    {:ok, metadata} = Metric.metadata(metric)

    if Sanbase.DateTimeUtils.str_to_sec(interval) <
         Sanbase.DateTimeUtils.str_to_sec(metadata.min_interval) do
      {:ok, metadata.min_interval}
    else
      {:ok, interval}
    end
  end

  defp maybe_enrich_with_labels("eth2_top_stakers", data), do: {:ok, data}

  defp maybe_enrich_with_labels(_metric, [%{address: address} | _] = data)
       when is_binary(address) do
    addresses = Enum.map(data, & &1.address) |> Enum.uniq()

    {:ok, labels} = Sanbase.Clickhouse.Label.get_address_labels("ethereum", addresses)

    labeled_data =
      Enum.map(data, fn %{address: address} = elem ->
        address_labels = Map.get(labels, address, []) |> Enum.map(& &1.name)
        Map.put(elem, :labels, address_labels)
      end)

    {:ok, labeled_data}
  end

  defp maybe_enrich_with_labels(_metric, data), do: {:ok, data}

  defp transform_interval("all_spent_coins_cost", interval) do
    Enum.max([Sanbase.DateTimeUtils.str_to_days(interval), 1])
    |> to_string()
    |> Kernel.<>("d")
  end

  defp transform_interval(_, interval), do: interval

  @metrics_allowed_missing_from [
    "all_spent_coins_cost",
    "eth2_staked_amount_per_label"
  ]
  # All histogram metrics except "all_spent_coins_cost" require `from` argument
  defp valid_histogram_args?(metric, args) do
    if metric in @metrics_allowed_missing_from or Map.get(args, :from) do
      true
    else
      {:error, "Missing required `from` argument"}
    end
  end

  defp valid_owners_labels_selection?(%{selector: selector} = _args) do
    cond do
      Map.has_key?(selector, :label) and Map.has_key?(selector, :labels) ->
        {:error, "Cannot use both 'label' and 'labels' fields at the same time."}

      Map.has_key?(selector, :owner) and Map.has_key?(selector, :owners) ->
        {:error, "Cannot use both 'owner' and 'owners' fields at the same time."}

      Map.has_key?(selector, :labels) and selector.labels == [] ->
        {:error, "The 'labels' selector field must not be an empty list."}

      Map.has_key?(selector, :owners) and selector.owners == [] ->
        {:error, "The 'owners' selector field must not be an empty list."}

      true ->
        true
    end
  end

  defp valid_owners_labels_selection?(_), do: true

  defp valid_timeseries_selection?(requested_fields, args) do
    aggregation = Map.get(args, :aggregation, nil)
    value_requested? = MapSet.member?(requested_fields, "value")
    value_ohlc_requested? = MapSet.member?(requested_fields, "valueOhlc")

    cond do
      aggregation == :ohlc && value_requested? ->
        {:error, "Field value shouldn't be selected when using aggregation ohlc"}

      value_ohlc_requested? && aggregation != :ohlc ->
        {:error, "Selected field valueOhlc works only with aggregation ohlc"}

      value_requested? and value_ohlc_requested? ->
        {:error, "Cannot select value and valueOhlc fields at the same time"}

      true ->
        true
    end
  end

  defguard has_binary_key?(selector, key)
           when is_map_key(selector, key) and
                  is_binary(:erlang.map_get(key, selector))

  defp valid_metric_selector_pair?("social_active_users", selector)
       when not has_binary_key?(selector, :source) do
    {:error,
     """
     The 'social_active_users' metric provides data for a social 'source' argument \
     (twitter, telegram, etc.). All the slug-related arguments are ignored. \
     Provide a 'source' argument.
     """}
  end

  defp valid_metric_selector_pair?(_metric, _selector), do: true

  defp maybe_filter_incomplete_metrics(metrics, nil = _has_incomplete_data), do: metrics

  defp maybe_filter_incomplete_metrics(metrics, true = _has_incomplete_data) do
    incomplete_metrics = Metric.incomplete_metrics()

    MapSet.intersection(MapSet.new(incomplete_metrics), MapSet.new(metrics))
    |> Enum.to_list()
  end

  defp maybe_filter_incomplete_metrics(metrics, false = _has_incomplete_data) do
    incomplete_metrics = Metric.incomplete_metrics()

    metrics -- incomplete_metrics
  end

  defp maybe_apply_regex_filter(metrics, nil), do: metrics

  defp maybe_apply_regex_filter(metrics, regex) do
    {:ok, regex} = Regex.compile(regex)
    Enum.filter(metrics, fn metric -> Regex.match?(regex, metric) end)
  end

  defp remove_hidden_metrics(metrics) do
    hidden_metrics = Sanbase.Metric.hidden_metrics()

    metrics
    |> Enum.reject(&(&1 in hidden_metrics))
  end

  defp maybe_remove_experimental_metrics(metrics, "alpha") do
    metrics
  end

  defp maybe_remove_experimental_metrics(metrics, "beta") do
    metrics
    |> Enum.reject(&(&1 in Sanbase.Metric.alpha_metrics()))
  end

  defp maybe_remove_experimental_metrics(metrics, _) do
    metrics
    |> Enum.reject(&(&1 in Sanbase.Metric.experimental_metrics()))
  end
end
