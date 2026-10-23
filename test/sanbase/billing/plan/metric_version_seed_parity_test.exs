Code.require_file("priv/repo/migrations/20261014084308_create_metric_version_plan_access.exs")

defmodule Sanbase.Billing.Plan.MetricVersionSeedParityTest do
  @moduledoc ~s"""
  The plan access the migration seeds gives every alias row the same answer as the
  rules that were hardcoded before it (master's `MetricVersionAccess`,
  `Sanbase.Metric.Version` and `ApiAccessChecker.metric_version_buckets/4`, copied
  below as `old_check/3`), for every kind of caller, plan, interval and trial.
  """
  use Sanbase.DataCase, async: false

  alias Sanbase.Accounts.User
  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Plan.MetricVersionAccess
  alias Sanbase.Billing.Subscription
  alias Sanbase.Metric.VersionAlias
  alias Sanbase.Repo
  alias Sanbase.Repo.Migrations.CreateMetricVersionPlanAccess

  @api 1
  @sanbase 2

  # The rows the alias migrations leave in the database, then versions of every
  # shape the seed's patterns tell apart.
  @rows [
    {"global", "1.0", "original:v1"},
    {"social", "2.0", "modern:v1"},
    {"social", "2.1", "modern_pit:v1"},
    {"social", "2.1.1", "modern_pit:v1.1"},
    {"social", "2.1.2", "modern_pit:v1.2"},
    {"social", "3.0", "stock:v1"},
    {"social", "3.1", "stock_pit:v1"},
    {"github", "2.0", "modern:v1"},
    {"global", "1.1", "edge_base:v1"},
    {"global", "1.0.1", "edge_base:v2"},
    {"global", "2.0.1", "edge_standard:v1"},
    {"global", "4.0", "edge_standard:v2"},
    {"global", "10.0", "edge_standard:v3"},
    {"global", "4.1", "edge_pit:v1"},
    {"global", "4.1.1", "edge_pit:v2"},
    {"global", "10.2", "edge_pit:v3"},
    {"github", "3.0", "edge_github:v1"},
    {"github", "3.1", "edge_github:v2"},
    {"social", "2.0.1", "edge_social:v1"}
  ]

  @metrics %{"m_global" => "global", "m_social" => "social", "m_github" => "github"}

  setup do
    Repo.delete_all(VersionAlias)

    for {scope, num, name} <- @rows do
      {:ok, _} = VersionAlias.create(%{scope: scope, version_num: num, version_name: name})
    end

    for sql <- CreateMetricVersionPlanAccess.seed_sql(), do: Repo.query!(sql)
    VersionAlias.clear_cache()
    :ok
  end

  test "every alias row gets the answer the hardcoded rules gave" do
    mismatches =
      with_scopes(fn ->
        for {metric, scope} <- @metrics,
            version <- versions_seen_by(scope),
            {label, context} <- callers(),
            old = old_check(scope, version, context),
            new = new_check(metric, version, context),
            old != new,
            do: {scope, version, label, old: old, new: new}
      end)

    assert mismatches == []
  end

  test "a github metric using a global row follows that row, where the old rules made it free" do
    with_scopes(fn ->
      assert old_check("github", "4.0", %{auth: %{auth_method: :none}}) == :ok
      assert new_check("m_github", "4.0", %{auth: %{auth_method: :none}}) == :denied
    end)
  end

  test "a version without an alias row is denied where the old rules allowed it" do
    with_scopes(fn ->
      context = apikey(sub(@api, "BUSINESS_MAX", "year"))

      assert old_check("global", "5.0", context) == :ok
      assert new_check("m_global", "5.0", context) == :denied
    end)
  end

  # The github scope also sees the global rows, but the old rules made every github
  # version free whatever its number - the next test covers that difference.
  defp versions_seen_by("github") do
    for {row_scope, num, _} <- @rows,
        row_scope == "github" or (row_scope == "global" and String.starts_with?(num, "1.")),
        uniq: true,
        do: num
  end

  defp versions_seen_by(scope) do
    for {row_scope, num, _} <- @rows, row_scope in [scope, "global"], uniq: true, do: num
  end

  defp with_scopes(fun) do
    Sanbase.Mock.prepare_mock(Sanbase.Metric, :version_scope, fn metric ->
      Map.get(@metrics, metric, "global")
    end)
    |> Sanbase.Mock.run_with_mocks(fun)
  end

  defp new_check(metric, version, context) do
    case MetricVersionAccess.check(metric, version, context) do
      :ok -> :ok
      {:error, _} -> :denied
    end
  end

  # Every kind of caller the old rules told apart.
  defp callers() do
    api_plans = [
      "FREE",
      "ESSENTIAL",
      "PRO",
      "BUSINESS_PRO",
      "BUSINESS_MAX",
      "INSTITUTIONAL",
      "ENTERPRISE",
      "BUNDLE"
    ]

    sanbase_plans = ["FREE", "BASIC", "PRO", "PRO_PLUS", "MAX"]

    api_subs =
      for plan <- api_plans,
          interval <- ["month", "year"],
          status <- [:active, :trialing],
          do: sub(@api, plan, interval, status)

    sanbase_subs =
      for plan <- sanbase_plans, interval <- ["month", "year"], do: sub(@sanbase, plan, interval)

    [
      {"anonymous", %{auth: %{auth_method: :none}, requested_product_id: @sanbase}},
      {"basic", %{auth: %{auth_method: :basic}}},
      {"apikey, no subscription", apikey(nil)}
    ] ++
      for(s <- api_subs ++ sanbase_subs, do: {"apikey #{describe(s)}", apikey(s)}) ++
      for(
        s <- api_subs ++ sanbase_subs,
        product <- [@sanbase, @api],
        do: {"jwt on #{product} #{describe(s)}", jwt(s, product)}
      )
  end

  defp sub(product_id, name, interval, status \\ :active) do
    %Subscription{
      status: status,
      plan: %Plan{name: name, interval: interval, product_id: product_id}
    }
  end

  defp describe(%Subscription{plan: plan, status: status}),
    do: "#{plan.product_id}/#{plan.name}/#{plan.interval}/#{status}"

  defp apikey(subscription) do
    by_product = if subscription, do: %{subscription.plan.product_id => subscription}, else: %{}

    %{
      auth: %{
        auth_method: :apikey,
        current_user: %User{id: 1},
        subscription: subscription,
        subscriptions_by_product: by_product
      },
      requested_product_id: @api
    }
  end

  defp jwt(subscription, requested_product_id) do
    %{
      auth: %{
        auth_method: :user_token,
        current_user: %User{id: 1},
        subscription: subscription,
        plan: Subscription.plan_name(subscription)
      },
      requested_product_id: requested_product_id
    }
  end

  # --- The rules as they were hardcoded on master -------------------------------------

  defp old_check(scope, version, context) do
    case old_bucket(scope, version) do
      :base ->
        :ok

      bucket ->
        case old_caller(context) do
          :unrestricted ->
            :ok

          caller ->
            case old_allowed_buckets(caller) do
              :all -> :ok
              buckets -> if bucket in buckets, do: :ok, else: :denied
            end
        end
    end
  end

  defp old_bucket(scope, version) do
    cond do
      scope in ["github"] -> :base
      classify(version) == :other -> :pit
      true -> classify(version)
    end
  end

  # Sanbase.Metric.Version.classify/1
  defp classify(version) do
    case version |> String.split(".") |> Enum.map(&Integer.parse/1) do
      [{1, ""} | rest] -> if valid_rest?(rest), do: :base, else: :other
      [{_major, ""}, {0, ""} | rest] -> if valid_rest?(rest), do: :standard, else: :other
      [{_major, ""}, {_minor, ""} | rest] -> if valid_rest?(rest), do: :pit, else: :other
      _ -> :other
    end
  end

  defp valid_rest?(rest), do: Enum.all?(rest, &match?({_, ""}, &1))

  defp old_caller(%{auth: %{auth_method: :basic}}), do: :unrestricted
  defp old_caller(%{auth: %{auth_method: :none}}), do: :anonymous

  defp old_caller(%{auth: %{auth_method: :apikey, current_user: _} = auth}) do
    subscription =
      Subscription.current_subscription_from_auth(auth, @api) || auth[:subscription]

    %{
      requested_product: "SANAPI",
      subscription: subscription,
      plan_name: Subscription.plan_name(subscription)
    }
  end

  defp old_caller(%{requested_product_id: product_id} = context) when is_integer(product_id) do
    %{
      requested_product: Sanbase.Billing.Product.code_by_id(product_id),
      subscription: context[:auth][:subscription],
      plan_name: context[:auth][:plan] || "FREE"
    }
  end

  defp old_caller(_context), do: :unrestricted

  defp old_allowed_buckets(:anonymous), do: [:base]

  # AccessChecker -> StandardAccessChecker -> Api/SanbaseAccessChecker.metric_version_buckets
  defp old_allowed_buckets(%{
         requested_product: requested_product,
         subscription: sub,
         plan_name: plan_name
       }) do
    plan =
      case Plan.type(plan_name) do
        :bundle -> Plan.Bundle.equivalent_standard_plan()
        :standard -> plan_name
      end

    case requested_product do
      "SANBASE" ->
        :all

      "SANAPI" ->
        case sub && Sanbase.Billing.Product.code_by_id(sub.plan.product_id) do
          product when product in [nil, "SANAPI"] ->
            case {plan, sub && sub.plan.interval, match?(%{status: :trialing}, sub)} do
              {"BUSINESS_PRO", _, _} -> [:base, :standard]
              {"BUSINESS_MAX", "year", false} -> [:base, :standard, :pit]
              {"BUSINESS_MAX", _, _} -> [:base, :standard]
              _ -> [:base]
            end

          _ ->
            [:base]
        end
    end
  end
end
