defmodule Sanbase.Billing.Plan.MetricVersionAccess do
  @moduledoc ~s"""
  Decides whether a GraphQL request may use a given metric version.

  The rules are data, stored with the version's alias row in the metric's version
  scope (`Sanbase.Metric.VersionAlias`):

    * `exposed_in` - the products the version can be used in at all.
    * `plan_access` - the plans that may use it on each product
      (`Sanbase.Metric.VersionPlanAccess`). Without a matching row the version is
      denied, so a version without an alias row is available to no plan.

  The default version is always available.

  The product is decided by how the caller authenticated, which the server verifies,
  and never by the `Origin` or `User-Agent` headers, which the caller controls:

    * basic auth - every version.
    * JWT (the Sanbase web app) - the SANBASE rows, for the Sanbase plan.
    * apikey - the SANAPI rows, for the key owner's SanAPI subscription, whatever the
      user agent. Sansheets runs on an apikey and gets the same rules. A Sanbase
      subscription does not count on SanAPI - its owner is FREE there.
    * anonymous - FREE, and only versions that both products allow. So is any
      request that did not go through the auth plug, such as one over the websocket.

  Plan access is behind the `:enforce` flag (`METRIC_VERSION_ACCESS_ENFORCE`). While it
  is off, a request that would be denied is logged and then allowed, so the impact can
  be measured before any customer loses access. `exposed_in` is always enforced - every
  version is exposed everywhere until an admin changes it.
  """

  require Logger

  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Product
  alias Sanbase.Billing.Subscription
  alias Sanbase.Metric.VersionAlias
  alias Sanbase.Metric.VersionPlanAccess

  @products VersionPlanAccess.products()
  @product_label %{"SANAPI" => "SanAPI", "SANBASE" => "Sanbase"}
  @exposure_label %{"api_only" => "SanAPI", "sanbase_only" => "Sanbase"}

  @spec check(String.t(), String.t(), map()) :: :ok | {:error, String.t()}
  def check(metric, version, context) do
    # Every caller has the default version, so the common case needs no subscription
    # lookup.
    if version == Sanbase.Metric.default_version() do
      :ok
    else
      case caller(context) do
        :unrestricted -> :ok
        caller -> check_caller(metric, version, caller, context)
      end
    end
  end

  @doc """
  The versions of the metric the caller can use - the ones `check/3` lets through.
  """
  @spec usable_versions(String.t(), [String.t()], map()) :: [String.t()]
  def usable_versions(metric, versions, context) do
    case caller(context) do
      :unrestricted -> versions
      caller -> filter_usable(metric, versions, caller, context[:auth][:current_user])
    end
  end

  @doc """
  The versions of the metric a plan can use on the product ("SANAPI" or "SANBASE").

  With `:subscription` (the caller's own plan, also when it is `nil` - no
  subscription) the plan is judged by that subscription's billing interval and trial.
  Without the key the plan is judged at its best - any billing interval, not on
  trial - as it answers what the plan can give. `:user` adds the versions the user
  is exempt for.
  """
  @spec plan_versions(String.t(), [String.t()], String.t(), String.t(), keyword()) ::
          [String.t()]
  def plan_versions(metric, versions, product, plan_name, opts \\ [])
      when product in @products do
    subscription = Keyword.get(opts, :subscription)
    caller = new_caller(product, subscription, plan_name, standard_plan(plan_name, product))

    # FREE has no subscription, so it never has a billing interval to be at its best in.
    caller =
      if Keyword.has_key?(opts, :subscription) or plan_name == "FREE",
        do: caller,
        else: %{caller | interval: :any}

    filter_usable(metric, versions, caller, Keyword.get(opts, :user))
  end

  @doc """
  The versions of the metric the caller's own plan can use on the product - what
  `check/3` lets through for the caller's requests to that product. A web app user
  asking about SanAPI is judged as their API key would be. Otherwise, on the other
  product, the caller's plan is judged there by `plan_versions/5`.
  """
  @spec own_plan_versions(String.t(), [String.t()], String.t(), String.t(), map()) ::
          [String.t()]
  def own_plan_versions(metric, versions, product, plan_name, context)
      when product in @products do
    user = context[:auth][:current_user]

    case caller(context) do
      :unrestricted ->
        versions

      %{product: ^product} = caller ->
        filter_usable(metric, versions, caller, user)

      %{product: "SANBASE"} when product == "SANAPI" ->
        filter_usable(metric, versions, apikey_caller(context), user)

      _anonymous_or_other_product ->
        plan_versions(metric, versions, product, plan_name,
          subscription: context[:auth][:subscription],
          user: user
        )
    end
  end

  # The caller as their API key requests are judged - the same subscriptions, by the
  # SanAPI rules of `caller/1`.
  defp apikey_caller(%{auth: %{current_user: %{}} = auth}),
    do: caller(%{auth: Map.put(auth, :auth_method, :apikey)})

  defp apikey_caller(_context), do: :anonymous

  defp filter_usable(metric, versions, caller, user) do
    scope = Sanbase.Metric.version_scope(metric)
    enforce? = enforce?()

    Enum.filter(versions, fn version ->
      row = VersionAlias.get(version, scope)

      cond do
        # Experimental versions have their own alpha-only rule and never reach `check/3`.
        version =~ "Experimental" -> true
        version == Sanbase.Metric.default_version() -> true
        not exposed?(row, caller) -> false
        not enforce? -> true
        true -> allowed?(row, caller) or exempt?(version, user)
      end
    end)
  end

  defp check_caller(metric, version, caller, context) do
    scope = Sanbase.Metric.version_scope(metric)
    row = VersionAlias.get(version, scope)

    cond do
      not exposed?(row, caller) ->
        log("Not exposed", metric, version, "not_exposed", caller, context)

        {:error,
         "Metric version #{VersionAlias.to_version_name(version, scope)} is available " <>
           "only in #{@exposure_label[row.exposed_in]}."}

      allowed?(row, caller) ->
        :ok

      exempt?(version, context[:auth][:current_user]) ->
        log("Exempt", metric, version, denial_reason(row), caller, context)
        :ok

      true ->
        deny(metric, version, row, caller, context)
    end
  end

  @doc false
  def enforce?() do
    Sanbase.Utils.Config.module_get_boolean(__MODULE__, :enforce) == true
  end

  defp exposed?(row, :anonymous), do: Enum.all?(@products, &VersionAlias.exposed_in?(row, &1))
  defp exposed?(row, %{product: product}), do: VersionAlias.exposed_in?(row, product)

  defp allowed?(nil, _caller), do: false

  defp allowed?(row, :anonymous) do
    Enum.all?(@products, fn product ->
      Enum.any?(row.plan_access, &VersionPlanAccess.matches?(&1, product, "FREE", nil, false))
    end)
  end

  defp allowed?(row, caller) do
    %{product: product, plan: plan, interval: interval, trialing?: trialing?} = caller

    Enum.any?(
      row.plan_access,
      &VersionPlanAccess.matches?(&1, product, plan, interval, trialing?)
    )
  end

  # Users listed in `METRIC_VERSION_ACCESS_EXEMPT_USER_IDS` keep the 2.0 family
  # (modern:v1 and its non point-in-time updates, 2.0.x) whatever their plan. It is a
  # grandfathering exception for Sanbase MAX customers who already used it through the
  # API before the restriction - nothing else about their plan changes.
  @exempt_version_family "2.0"

  defp exempt?(version, user) do
    exempt_version?(version) and exempt_user?(user)
  end

  defp exempt_version?(version) do
    version == @exempt_version_family or
      String.starts_with?(version, @exempt_version_family <> ".")
  end

  defp exempt_user?(%{id: user_id}), do: user_id in exempt_user_ids()
  defp exempt_user?(_), do: false

  # A comma-separated list of user ids. Anything that is not an integer is ignored.
  defp exempt_user_ids() do
    (Sanbase.Utils.Config.module_get(__MODULE__, :exempt_user_ids) || "")
    |> to_string()
    |> String.split(",", trim: true)
    |> Enum.flat_map(fn id ->
      case Integer.parse(String.trim(id)) do
        {id, ""} -> [id]
        _ -> []
      end
    end)
  end

  defp caller(%{auth: %{auth_method: :basic}}), do: :unrestricted

  defp caller(%{auth: %{auth_method: :none}}), do: :anonymous

  # The auth plug resolves a Sansheets apikey to the Sanbase product, preferring the
  # Sanbase subscription. For versions the key is judged by the SanAPI rules, so the
  # SanAPI subscription is preferred instead - the same order a plain apikey gets.
  defp caller(%{auth: %{auth_method: :apikey, current_user: _} = auth}) do
    subscription =
      Subscription.current_subscription_from_auth(auth, Product.product_api()) ||
        auth[:subscription]

    plan_name = Subscription.plan_name(subscription)

    case subscription_product(subscription) do
      product when product in [nil, "SANAPI"] ->
        new_caller("SANAPI", subscription, plan_name, standard_plan(plan_name, "SANAPI"))

      # A Sanbase subscription gives nothing on SanAPI - its owner is FREE there.
      _ ->
        new_caller("SANAPI", subscription, plan_name, "FREE")
    end
  end

  # The auth plug has already turned custom plans and bundles into the plan they get
  # on the requested product.
  defp caller(%{requested_product_id: product_id} = context) when is_integer(product_id) do
    product = Product.code_by_id(product_id)
    plan_name = context[:auth][:plan] || "FREE"
    plan = standard_plan(plan_name, product)

    new_caller(product, context[:auth][:subscription], plan_name, plan)
  end

  # Anything else did not go through the auth plug - a GraphQL document sent over the
  # websocket (`SanbaseWeb.UserSocket` mounts Absinthe with no auth in the context),
  # or a context built by hand. Nothing vouches for the caller, so it is anonymous.
  defp caller(_context), do: :anonymous

  defp new_caller(product, subscription, plan_name, plan) do
    caller = %{
      product: product,
      subscription: subscription,
      subscription_product: subscription_product(subscription),
      plan_name: plan_name,
      plan: plan,
      interval: interval(subscription),
      trialing?: trialing?(subscription)
    }

    # A subscription of the other product that gives nothing here (a Sanbase plan on
    # an apikey, a bundle in the web app) is FREE - with no billing interval or trial,
    # as FREE never has one. Its own plan name is kept for the message and the log.
    case caller do
      %{plan: "FREE", subscription_product: sub_product} when sub_product not in [nil, product] ->
        %{
          caller
          | plan_name: Subscription.plan_name(subscription),
            interval: nil,
            trialing?: false
        }

      caller ->
        caller
    end
  end

  # Custom plans and bundles match the rows of the standard plan they are based on.
  defp standard_plan(plan_name, product) do
    base_plan =
      case Plan.type(plan_name) do
        :bundle -> Plan.Bundle.equivalent_standard_plan()
        :custom -> Plan.CustomPlan.Access.restricted_access_as_plan(plan_name, product)
        :standard -> plan_name
      end

    if is_binary(base_plan), do: Plan.canonical_name(base_plan), else: base_plan
  end

  defp subscription_product(%{plan: %{product_id: product_id}}),
    do: Product.code_by_id(product_id)

  defp subscription_product(_), do: nil

  defp interval(%{plan: %{interval: interval}}), do: interval
  defp interval(_), do: nil

  defp trialing?(subscription), do: match?(%{status: :trialing}, subscription)

  defp caller_description(:anonymous), do: "Anonymous requests have access to"

  # The plan as it was judged: a Sanbase subscription on an apikey is FREE on SanAPI.
  defp caller_description(
         %{plan: "FREE", product: product, subscription_product: sub_product} = caller
       )
       when sub_product not in [nil, product] do
    %{plan_name: plan_name, subscription_product: subscription_product} = caller

    "Your plan (#{@product_label[subscription_product]} #{plan_name}, which is FREE on " <>
      "#{@product_label[product]}) has access to"
  end

  defp caller_description(%{plan_name: plan_name, interval: interval, trialing?: trialing?}) do
    plan =
      [plan_name, interval, if(trialing?, do: "trial")]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    "Your plan (#{plan}) has access to"
  end

  # Anonymous requests have FREE on both products, so the version is open to some
  # signed-in plan - say which, per product.
  defp requirement(row, :anonymous) do
    case plan_access(row) do
      [] ->
        "is not available to any plan"

      rows ->
        plans =
          for product <- @products,
              product_rows = Enum.filter(rows, &(&1.product == product)),
              product_rows != [],
              do:
                "#{@product_label[product]} plans: " <>
                  Enum.map_join(product_rows, ", ", &plan_description/1)

        "needs an API key or a Sanbase login (#{Enum.join(plans, "; ")})"
    end
  end

  defp requirement(row, %{product: product}) do
    case Enum.filter(plan_access(row), &(&1.product == product)) do
      [] ->
        "is not available to any #{@product_label[product]} plan"

      rows ->
        "requires one of these #{@product_label[product]} plans: " <>
          Enum.map_join(rows, ", ", &plan_description/1)
    end
  end

  defp plan_description(%VersionPlanAccess{} = row) do
    qualifiers =
      [
        row.billing_interval != "any" && "#{row.billing_interval}ly",
        not row.accessible_if_trial && "no trial"
      ]
      |> Enum.filter(& &1)

    plan = if row.plan == VersionPlanAccess.any_plan(), do: "any plan", else: row.plan

    case qualifiers do
      [] -> plan
      _ -> "#{plan} (#{Enum.join(qualifiers, ", ")})"
    end
  end

  # Cheapest plan first, the order the admin page shows them in.
  defp plan_access(nil), do: []

  defp plan_access(row) do
    Enum.sort_by(row.plan_access, fn access ->
      order = [VersionPlanAccess.any_plan() | VersionPlanAccess.plans(access.product)]
      {Enum.find_index(order, &(&1 == access.plan)) || length(order), access.plan}
    end)
  end

  # Users see version names, the same ones `availableVersions` returns. The default
  # version is always included, even when the alias table cannot be read.
  defp allowed_version_names(scope, caller) do
    allowed =
      for row <- VersionAlias.rows(scope),
          exposed?(row, caller) and allowed?(row, caller),
          do: row.version_num

    [Sanbase.Metric.default_version() | allowed]
    |> Enum.uniq()
    |> Enum.sort_by(&VersionAlias.sort_key/1)
    |> Enum.map_join(", ", &VersionAlias.to_version_name(&1, scope))
  end

  defp denial_reason(nil), do: "no_alias"
  defp denial_reason(_row), do: "no_plan_access"

  defp deny(metric, version, row, caller, context) do
    enforce? = enforce?()
    scope = Sanbase.Metric.version_scope(metric)

    log(
      if(enforce?, do: "Denied", else: "Would deny"),
      metric,
      version,
      denial_reason(row),
      caller,
      context
    )

    if enforce? do
      {:error,
       "Metric version #{VersionAlias.to_version_name(version, scope)} " <>
         "#{requirement(row, caller)}. #{caller_description(caller)} " <>
         "#{allowed_version_names(scope, caller)}."}
    else
      :ok
    end
  end

  # Blocked calls are not exported to api_call_data (error queries never are), so this
  # line is the only record of them. key=value so Loki can aggregate with `| logfmt`.
  defp log(outcome, metric, version, reason, caller, context) do
    user = context[:auth][:current_user]

    # The interval and trial the decision used, and the product of the subscription
    # the plan comes from - a Sanbase PRO key is FREE on SanAPI, not SanAPI PRO.
    {product, plan, subscription_product, interval, trial?} =
      case caller do
        :anonymous ->
          {nil, "anonymous", nil, nil, false}

        %{product: product, plan_name: plan_name} = caller ->
          {product, plan_name, caller.subscription_product, caller.interval, caller.trialing?}
      end

    fields = [
      user_id: user && user.id,
      auth_method: context[:auth][:auth_method],
      product: product,
      plan: plan,
      subscription_product: subscription_product,
      interval: interval,
      trial: trial?,
      metric: metric,
      version: version,
      version_name: VersionAlias.to_version_name(version, Sanbase.Metric.version_scope(metric)),
      reason: reason
    ]

    Logger.info(
      "[MetricVersionAccess] #{outcome} " <>
        Enum.map_join(fields, " ", fn {key, value} -> "#{key}=#{value}" end)
    )
  end
end
