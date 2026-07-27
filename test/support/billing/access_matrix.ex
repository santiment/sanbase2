defmodule Sanbase.Billing.AccessMatrix do
  @moduledoc ~s"""
  Builds a snapshot of every plan-dependent access and quota answer in the system.

  This exists to support a *characterization* test: it does not assert that any
  answer is correct, only that it does not change. See
  `Sanbase.Billing.AccessMatrixCharacterizationTest` and
  `docs/composable-api-plans-handover.md` §7.4.

  ## Why the outputs are captured as data, including failures

  Several of the functions snapshotted here dispatch on the plan name with a
  `case` that has no catch-all clause, so an unknown plan name raises rather
  than returning a value. `PREMIUM` is a real example: it is a valid plan name
  according to `Sanbase.Billing.Plan.plan_name/1`, but no window, quota or
  limit function has a clause for it.

  Raising is therefore part of today's observable behavior and must be pinned
  like any other answer. Exceptions are recorded as `%{"__raise__" => "..."}`
  rather than allowed to abort the build. Only the exception *type* is stored —
  messages embed inspected values and are not stable enough to diff.

  ## What is deliberately not captured

  `get_available_metrics_for_plan/3` returns the full metric list, which grows
  whenever a metric is added to the registry. Pinning it would make the fixture
  churn on unrelated work. It is covered instead by the item sample below (same
  underlying `plan_has_access?/3` logic) and by the dispatch smoke matrix, which
  asserts it does not raise.
  """

  alias Sanbase.ApiCallLimit
  alias Sanbase.Billing.Plan.AccessChecker
  alias Sanbase.Billing.Plan.SanbaseAccessChecker
  alias Sanbase.Queries.Authorization

  @products ["SANAPI", "SANBASE"]

  @doc """
  Canonical plan names as they reach the access layer.

  These are the outputs of `Plan.plan_name/1`, not the raw `plans.name` values —
  `ESSENTIAL` is normalised to `BASIC` before any access check runs, so it does
  not appear here.
  """
  def standard_plan_names do
    [
      "FREE",
      "BASIC",
      "PRO",
      "PRO_PLUS",
      "MAX",
      "BUSINESS_PRO",
      "BUSINESS_MAX",
      "CUSTOM",
      "PREMIUM"
    ]
  end

  @doc """
  A fixed sample of metrics, queries and signals.

  Hardcoded rather than derived from the registry so that the fixture does not
  churn when metrics are added. The sample spans free and restricted access
  levels and several `min_plan` values, which is what makes it sensitive to a
  plan-dispatch regression: a misrouted plan changes every item's answer at once.
  """
  def sample_items do
    [
      {:metric, "price_usd"},
      {:metric, "mvrv_usd"},
      {:metric, "active_addresses_24h"},
      {:metric, "daily_active_addresses"},
      {:metric, "social_volume_total"},
      {:metric, "dev_activity"},
      {:metric, "nft_market_volume"},
      {:query, :current_user},
      {:query, :all_projects},
      {:query, :project_by_slug},
      {:query, :history_price},
      {:query, :top_holders},
      {:query, :realtime_top_holders},
      {:query, :gas_used},
      {:query, :miners_balance}
    ]
  end

  @doc """
  Build the full matrix.

  ## Options

    * `:plan_names` - plan names to snapshot. Defaults to `standard_plan_names/0`.
      Pass extra names (e.g. a seeded `CUSTOM_*` plan) to pin those paths too.
  """
  def build(opts \\ []) do
    plan_names = Keyword.get(opts, :plan_names, standard_plan_names())

    Map.new(@products, fn product ->
      {product, Map.new(plan_names, &{&1, plan_snapshot(product, &1)})}
    end)
  end

  defp plan_snapshot(product, plan_name) do
    %{
      "plan_level" => plan_level(product, plan_name),
      "items" => Map.new(sample_items(), &{item_key(&1), item_snapshot(&1, product, plan_name)})
    }
  end

  defp plan_level(product, plan_name) do
    # The api_call_limits table keys quotas by a product-prefixed, downcased
    # plan name rather than by the plan name itself.
    acl_plan = "#{product}_#{plan_name}" |> String.downcase()

    %{
      "acl_plan" => acl_plan,
      "api_call_limits" => safe(fn -> ApiCallLimit.plan_to_api_call_limits(acl_plan) end),
      "response_size_limits" =>
        safe(fn -> ApiCallLimit.plan_to_response_size_limits(acl_plan) end),
      "plan_has_limits?" => safe(fn -> ApiCallLimit.plan_has_limits?(acl_plan) end),
      "alerts_limit" => safe(fn -> SanbaseAccessChecker.alerts_limit(plan_name) end),
      "credits_limit" => safe(fn -> Authorization.credits_limit(product, plan_name) end),
      "query_executions_limit" =>
        safe(fn -> Authorization.query_executions_limit(product, plan_name) end),
      "clickhouse_repo" =>
        safe(fn -> Authorization.user_plan_to_dynamic_repo(product, plan_name) end)
    }
  end

  defp item_snapshot(item, product, plan_name) do
    %{
      "min_plan" => safe(fn -> AccessChecker.min_plan(item, product) end),
      "restricted?" => safe(fn -> AccessChecker.restricted?(item) end),
      "access?" => safe(fn -> AccessChecker.plan_has_access?(item, product, plan_name) end),
      # subscription_product can differ from requested_product (a SanAPI
      # subscriber hitting Sanbase, and vice versa). The window functions branch
      # on it, so both are captured.
      "windows" =>
        Map.new(
          @products,
          &{"subscription_product=" <> &1, windows(item, product, &1, plan_name)}
        )
    }
  end

  defp windows(item, requested_product, subscription_product, plan_name) do
    %{
      "historical_data_in_days" =>
        safe(fn ->
          AccessChecker.historical_data_in_days(
            item,
            requested_product,
            subscription_product,
            plan_name
          )
        end),
      "realtime_data_cut_off_in_days" =>
        safe(fn ->
          AccessChecker.realtime_data_cut_off_in_days(
            item,
            requested_product,
            subscription_product,
            plan_name
          )
        end)
    }
  end

  defp item_key({type, name}), do: "#{type}:#{name}"

  # Captures the answer, or the exception type if there is no answer. Recording
  # only the struct name keeps the fixture stable - exception messages embed
  # inspected values.
  defp safe(fun) do
    jsonable(fun.())
  rescue
    error -> %{"__raise__" => inspect(error.__struct__)}
  end

  defp jsonable(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp jsonable(nil), do: nil
  defp jsonable(value) when is_atom(value), do: inspect(value)
  defp jsonable(value) when is_list(value), do: Enum.map(value, &jsonable/1)

  defp jsonable(%{} = value) do
    Map.new(value, fn {k, v} -> {to_string(k), jsonable(v)} end)
  end
end
