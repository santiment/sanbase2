defmodule Sanbase.Billing.Plan.PlanMetricAccess do
  @moduledoc """
  What a plan gets for a metric, per channel (Sanbase app or API).

  Everything is derived from the access checkers, so the answers match what is
  enforced on real requests.
  """

  alias Sanbase.AvailableMetrics

  alias Sanbase.Billing.Plan.{
    AccessChecker,
    ApiAccessChecker,
    SanbaseAccessChecker
  }

  alias Sanbase.Cache.RehydratingCache
  alias Sanbase.Metric.Registry

  require Logger

  @type plan_key :: String.t()
  @type channel :: :sanbase | :api
  @type access ::
          :free
          | {:window, history_days :: pos_integer() | nil, lag_days :: pos_integer() | nil}
          | {:locked, min_plan_key :: plan_key() | nil}

  @type row :: %{
          id: String.t(),
          name: String.t(),
          metrics: [String.t()],
          category: String.t(),
          category_slug: String.t(),
          group: String.t() | nil,
          search_text: String.t(),
          access: %{{plan_key(), channel()} => access()}
        }

  @rows_cache_key {__MODULE__, :rows}
  @rows_ttl 3600
  @rows_refresh_time_delta 600
  # How long a caller waits for the first hydration before computing on its own.
  @rows_first_computation_wait 5_000
  # Without RehydratingCache, the synchronous result is kept this long, so the page
  # computes once per TTL and not once per request.
  @rows_fallback_cache_key {__MODULE__, :rows_fallback}
  @rows_fallback_ttl 300

  # A run of template placeholders, including ranges like "{{low}} and {{high}}".
  @placeholder_run ~r/\{\{[^}]*\}\}(?:\s*(?:and|to|-|,)\s*\{\{[^}]*\}\})*/
  @empty_brackets ~r/\(\s*\)|\[\s*\]/
  @leading_separators ~r/^[\s\-_,:;\/|]+/
  # Separators and connector words left dangling at the end once the placeholder
  # is gone: "MVRV for coins that moved in the past {{timebound}}" reads as
  # "MVRV for coins that moved".
  @dangling_tail ~r/(?:[\s\-_,:;\/|(]|\b(?:and|or|of|for|the|in|between|over|past|last|with|at|to|from|by)\b)+$/i

  @plans [
    %{key: "free", label: "Free", plan_name: "FREE", subscription_product: nil, includes: nil},
    %{
      key: "sanbase_pro",
      label: "Sanbase Pro",
      plan_name: "PRO",
      subscription_product: "SANBASE",
      includes: nil
    },
    %{
      key: "sanbase_max",
      label: "Sanbase Max",
      plan_name: "MAX",
      subscription_product: "SANBASE",
      includes: nil
    },
    %{
      key: "business_pro",
      label: "Business Pro",
      plan_name: "BUSINESS_PRO",
      subscription_product: "SANAPI",
      includes: "sanbase_pro"
    },
    %{
      key: "business_max",
      label: "Business Max",
      plan_name: "BUSINESS_MAX",
      subscription_product: "SANAPI",
      includes: "sanbase_max"
    }
  ]

  @channels [
    %{key: :sanbase, label: "In Sanbase", product: "SANBASE"},
    %{key: :api, label: "Via API", product: "SANAPI"}
  ]

  @doc """
  The plans shown on the metrics access page, in display order. `includes` is the
  key of the Sanbase plan a Business plan comes with (its access in Sanbase), or nil.
  """
  @spec plans() :: [map()]
  def plans(), do: @plans

  @spec channels() :: [map()]
  def channels(), do: @channels

  @spec access({:metric, String.t()}, plan_key, channel) :: access
  def access({:metric, _} = query, plan_key, channel) do
    plan = plan!(plan_key)
    product = channel!(channel).product
    subscription_product = plan.subscription_product || product

    # Same order as enforcement (AccessControl, Restrictions.get/6): the min plan is
    # checked first, so a free-access metric above the plan's min plan is locked.
    cond do
      not AccessChecker.plan_has_access?(query, product, plan.plan_name) ->
        {:locked, lowest_unlocking_plan(query, product)}

      not AccessChecker.restricted?(query) ->
        :free

      true ->
        history =
          AccessChecker.historical_data_in_days(
            query,
            product,
            subscription_product,
            plan.plan_name
          )

        lag =
          AccessChecker.realtime_data_cut_off_in_days(
            query,
            product,
            subscription_product,
            plan.plan_name
          )

        {:window, history, zero_to_nil(lag)}
    end
  end

  @doc "The plan-level window, independent of any metric: `{history_days, lag_days}`."
  @spec headline(plan_key, channel) :: {pos_integer() | nil, pos_integer() | nil}
  def headline(plan_key, channel) do
    plan = plan!(plan_key)
    product = channel!(channel).product
    subscription_product = plan.subscription_product || product
    module = checker_module(channel)

    {
      module.historical_data_in_days(subscription_product, plan.plan_name),
      zero_to_nil(module.realtime_data_cut_off_in_days(subscription_product, plan.plan_name))
    }
  end

  @doc ~s"""
  The rows of the metrics access page, served from `RehydratingCache` (refreshed
  every #{@rows_refresh_time_delta}s, kept for #{@rows_ttl}s), so visitors never wait
  on a rebuild. Before the first hydration has finished, or when the cache is not
  running, the rows are computed synchronously and kept in `Sanbase.Cache` for
  #{@rows_fallback_ttl}s.

  With `:use_rehydrating_cache` off (the test env) the cache is not touched at all:
  a registered closure would outlive the test that registered it.
  """
  @spec rows() :: [row]
  def rows() do
    if rehydrating_cache_enabled?() do
      case cached_rows() do
        {:ok, rows} when is_list(rows) -> rows
        error -> fallback_rows(error)
      end
    else
      compute_rows()
    end
  end

  # Sanbase.Cache runs in every container; the warning is logged only when the rows
  # are actually computed, not on every request served from the fallback.
  defp fallback_rows(error) do
    Sanbase.Cache.get_or_store({@rows_fallback_cache_key, @rows_fallback_ttl}, fn ->
      Logger.warning(
        "[PlanMetricAccess] Metrics access rows not cached (#{inspect(error)}), " <>
          "computing them synchronously."
      )

      compute_rows()
    end)
  end

  @doc ~s"""
  Build the page rows, uncached, in taxonomy order.

  Only metrics from `Sanbase.Metric.available_metrics/0` that are released and not
  deprecated appear. All the names a registry row resolves to (template variants,
  aliases) are one row with id `r-<registry id>`; should their access diverge, each
  distinct access is its own row, `r-<registry id>-<first metric>`. A metric not
  defined in the registry is its own row, `m-<metric>`. A metric mapped only to
  hidden groups is dropped (on its own, not with its row), and uncategorized rows go
  under "Other".

  Each row carries what the page filters on, computed once here: `category_slug`,
  and `search_text`, the display and technical names downcased.
  """
  @spec compute_rows() :: [row]
  def compute_rows() do
    registry_index = registry_index()
    categories_map = AvailableMetrics.metric_to_categories_map()

    {registry_metrics, code_metrics} =
      categories_map
      |> shown_metrics()
      |> Enum.split_with(&Map.has_key?(registry_index, &1))

    (registry_rows(registry_metrics, registry_index) ++ Enum.map(code_metrics, &code_row/1))
    |> Enum.map(&put_taxonomy(&1, categories_map))
    |> AvailableMetrics.sort_by_taxonomy()
    # Only the sort reads these; every page request copies the rows, so drop them.
    |> Enum.map(&Map.drop(&1, [:metric, :categories]))
  end

  defp shown_metrics(categories_map) do
    # `available_metrics/0` without options does not drop hidden metrics.
    hidden = Sanbase.Metric.hidden_metrics()

    Sanbase.Metric.available_metrics()
    |> Enum.filter(fn metric ->
      metric not in hidden and
        not only_in_hidden_groups?(Map.get(categories_map, metric, [])) and
        released?(metric)
    end)
  end

  defp rehydrating_cache_enabled?() do
    Application.get_env(:sanbase, :use_rehydrating_cache, true)
  end

  defp cached_rows() do
    case RehydratingCache.get(@rows_cache_key, @rows_first_computation_wait) do
      {:error, :not_registered} ->
        # `{:error, :already_registered}` means a concurrent caller won the race,
        # which is just as good.
        _ =
          RehydratingCache.register_function(
            fn -> {:ok, compute_rows()} end,
            @rows_cache_key,
            @rows_ttl,
            @rows_refresh_time_delta,
            "metrics access page rows"
          )

        RehydratingCache.get(@rows_cache_key, @rows_first_computation_wait)

      result ->
        result
    end
  catch
    # Not running (the test env), or a call timing out on an overloaded cache.
    :exit, _ -> {:error, :unavailable}
  end

  defp released?(metric) do
    case Sanbase.Metric.metadata(metric) do
      # Code-defined metrics carry `is_deprecated: nil`, which means not deprecated.
      {:ok, %{status: "released"} = metadata} -> Map.get(metadata, :is_deprecated) != true
      _ -> false
    end
  end

  # Every public name the registry defines => its registry row. Should several rows
  # resolve to one name, the one that can be shown (not deprecated, not hidden) wins,
  # then the lowest id, and the collisions are logged once per computation.
  defp registry_index() do
    candidates = registry_candidates()
    log_registry_collisions(candidates)

    Map.new(candidates, fn {metric, registries} ->
      {metric, Enum.min_by(registries, &{not shown_registry?(&1), &1.id})}
    end)
  end

  # Every public name => the distinct registry rows that resolve to it.
  defp registry_candidates() do
    Registry.all()
    |> Enum.flat_map(fn registry ->
      registry |> resolve_registry() |> Enum.map(&{&1.metric, registry})
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {metric, registries} -> {metric, Enum.uniq_by(registries, & &1.id)} end)
  end

  defp shown_registry?(registry), do: not (registry.is_deprecated or registry.is_hidden)

  defp log_registry_collisions(candidates) do
    collisions =
      for {metric, [_, _ | _] = registries} <- candidates do
        ids = registries |> Enum.map(& &1.id) |> Enum.sort() |> Enum.join(", ")
        "#{metric} (ids #{ids})"
      end

    if collisions != [] do
      Logger.warning(
        "[PlanMetricAccess] Metric names that several registry rows share: " <>
          Enum.join(Enum.sort(collisions), "; ")
      )
    end
  end

  defp resolve_registry(registry) do
    Registry.resolve_registry(registry)
  rescue
    # A broken template is not served by the registry adapter either.
    _ -> []
  end

  defp registry_rows(metrics, registry_index) do
    metrics
    |> Enum.group_by(&Map.fetch!(registry_index, &1).id)
    |> Enum.flat_map(fn {_id, [metric | _] = metrics} ->
      registry = Map.fetch!(registry_index, metric)

      # A deprecated or hidden registry row is dropped as a whole; its names are
      # indexed anyway so they never show up as code rows. Read from the DB row, so
      # an admin's change applies before the stored terms are refreshed.
      if shown_registry?(registry),
        do: registry_row_variants(registry, metrics),
        else: []
    end)
  end

  defp registry_row_variants(registry, metrics) do
    groups =
      metrics
      |> Enum.group_by(&access_map/1)
      |> Enum.map(fn {access, metrics} -> {access, Enum.sort(metrics)} end)

    split? = length(groups) > 1
    name = clean_name(registry.human_readable_name)

    Enum.map(groups, fn {access, [first | _] = metrics} ->
      id = if split?, do: "r-#{registry.id}-#{first}", else: "r-#{registry.id}"
      %{id: id, name: name || first, metrics: metrics, access: access}
    end)
  end

  defp code_row(metric) do
    %{
      id: "m-#{metric}",
      name: code_metric_name(metric),
      metrics: [metric],
      access: access_map(metric)
    }
  end

  defp code_metric_name(metric) do
    name =
      case Sanbase.Metric.human_readable_name(metric) do
        {:ok, name} -> clean_name(name)
        _ -> nil
      end

    name || metric
  end

  defp access_map(metric) do
    for %{key: plan} <- @plans, %{key: channel} <- @channels, into: %{} do
      {{plan, channel}, access({:metric, metric}, plan, channel)}
    end
  end

  # The display name with template placeholders and the separators they leave
  # behind removed. nil when nothing is left.
  defp clean_name(name) when is_binary(name) do
    name =
      if String.contains?(name, "{{") do
        name
        |> String.replace(@placeholder_run, " ")
        |> String.replace(@empty_brackets, " ")
        |> String.replace(@leading_separators, "")
        |> String.replace(@dangling_tail, "")
      else
        name
      end

    case name |> String.split() |> Enum.join(" ") do
      "" -> nil
      name -> name
    end
  end

  defp clean_name(_), do: nil

  defp put_taxonomy(%{name: name, metrics: metrics} = row, categories_map) do
    categories = metrics |> Enum.flat_map(&Map.get(categories_map, &1, [])) |> Enum.uniq()
    placement = AvailableMetrics.taxonomy_placement(categories)
    category = placement.category_name || "Other"

    row
    |> Map.put(:metric, hd(metrics))
    |> Map.put(:categories, categories)
    |> Map.put(:category, category)
    |> Map.put(:category_slug, slugify(category))
    |> Map.put(:group, placement.group_name)
    |> Map.put(:search_text, [name | metrics] |> Enum.join("\n") |> String.downcase())
  end

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp only_in_hidden_groups?([]), do: false

  defp only_in_hidden_groups?(categories) do
    hidden = AvailableMetrics.hidden_group_names()
    Enum.all?(categories, &(&1.group_name in hidden))
  end

  defp checker_module(:sanbase), do: SanbaseAccessChecker
  defp checker_module(:api), do: ApiAccessChecker

  defp lowest_unlocking_plan(query, product) do
    Enum.find_value(@plans, fn plan ->
      if AccessChecker.plan_has_access?(query, product, plan.plan_name), do: plan.key
    end)
  end

  defp zero_to_nil(0), do: nil
  defp zero_to_nil(value), do: value

  defp plan!(key),
    do:
      Enum.find(@plans, &(&1.key == key)) || raise(ArgumentError, "unknown plan #{inspect(key)}")

  defp channel!(key),
    do:
      Enum.find(@channels, &(&1.key == key)) ||
        raise(ArgumentError, "unknown channel #{inspect(key)}")
end
