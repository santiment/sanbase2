defmodule Sanbase.Billing.Plan.MetricVersionAccess do
  @moduledoc ~s"""
  Decides whether a GraphQL request may use a given metric version.

  The decision is keyed on how the caller authenticated, which the server verifies,
  and never on the `Origin` or `User-Agent` headers, which the caller controls:

    * basic auth - every version.
    * JWT (the Sanbase web app) - the Sanbase rules, which do not restrict versions yet.
    * apikey - the SanAPI rules for the key owner's subscription, whatever the user
      agent. Sansheets runs on an apikey and gets the same rules.
    * anonymous - version 1.0 only, whatever the origin.

  The entitlement matrix lives in
  `Sanbase.Billing.Plan.ApiAccessChecker.metric_version_buckets/4`.

  Enforcement is behind the `:enforce` flag (`METRIC_VERSION_ACCESS_ENFORCE`). While it
  is off, a request that would be denied is logged and then allowed, so the impact can
  be measured before any customer loses access.
  """

  require Logger

  alias Sanbase.Billing.Plan.AccessChecker
  alias Sanbase.Billing.Product
  alias Sanbase.Billing.Subscription
  alias Sanbase.Metric.Version
  alias Sanbase.Metric.VersionAlias

  @required_plan %{
    standard: "a SanAPI Business Pro or Business Max subscription",
    pit: "a paid yearly SanAPI Business Max subscription"
  }

  @spec check(String.t(), String.t(), map()) :: :ok | {:error, String.t()}
  def check(metric, version, context) do
    case bucket(version) do
      # Every caller has version 1.0, so the common case needs no subscription lookup.
      :base ->
        :ok

      bucket ->
        case caller(context) do
          :unrestricted ->
            :ok

          caller ->
            case allowed_buckets(caller) do
              :all ->
                :ok

              buckets ->
                cond do
                  bucket in buckets -> :ok
                  exempt?(version, context) -> exempt(metric, version, bucket, caller, context)
                  true -> deny(metric, version, bucket, buckets, caller, context)
                end
            end
        end
    end
  end

  # Users listed in `METRIC_VERSION_ACCESS_EXEMPT_USER_IDS` keep the 2.0 family
  # (modern:v1 and its non point-in-time updates, 2.0.x) whatever their plan. It is a
  # grandfathering exception for Sanbase MAX customers who already used it through the
  # API before the restriction - nothing else about their plan changes.
  @exempt_version_family "2.0"

  @doc false
  def enforce?() do
    Sanbase.Utils.Config.module_get_boolean(__MODULE__, :enforce) == true
  end

  defp exempt?(version, context) do
    exempt_version?(version) and exempt_user?(context[:auth][:current_user])
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

  # A non-numeric version that is not Experimental (those have their own rule and
  # never reach here) is treated as the most restricted bucket.
  defp bucket(version) do
    case Version.classify(version) do
      :other -> :pit
      bucket -> bucket
    end
  end

  defp caller(%{auth: %{auth_method: :basic}}), do: :unrestricted

  defp caller(%{auth: %{auth_method: :none}}), do: :anonymous

  # The auth plug resolves a Sansheets apikey to the Sanbase product, preferring the
  # Sanbase subscription. For versions the key is judged by the SanAPI rules, so the
  # SanAPI subscription is preferred instead - the same order a plain apikey gets.
  defp caller(%{auth: %{auth_method: :apikey, current_user: user} = auth}) do
    subscription =
      Subscription.current_subscription(user.id, Product.product_api()) || auth[:subscription]

    %{
      requested_product: "SANAPI",
      subscription: subscription,
      plan_name: Subscription.plan_name(subscription)
    }
  end

  defp caller(%{requested_product_id: product_id} = context) when is_integer(product_id) do
    %{
      requested_product: Product.code_by_id(product_id),
      subscription: context[:auth][:subscription],
      plan_name: context[:auth][:plan] || "FREE"
    }
  end

  # No resolved product means the request did not go through the auth plug (an
  # internal call), which is not something this restriction is about.
  defp caller(_context), do: :unrestricted

  defp allowed_buckets(:anonymous), do: [:base]

  defp allowed_buckets(caller) do
    %{requested_product: requested_product, subscription: subscription, plan_name: plan_name} =
      caller

    AccessChecker.metric_version_buckets(
      requested_product,
      subscription_product(subscription),
      plan_name,
      interval(subscription),
      trialing?(subscription)
    )
  end

  defp subscription_product(%{plan: %{product_id: product_id}}),
    do: Product.code_by_id(product_id)

  defp subscription_product(_), do: nil

  defp interval(%{plan: %{interval: interval}}), do: interval
  defp interval(_), do: nil

  defp trialing?(subscription), do: match?(%{status: :trialing}, subscription)

  defp caller_description(:anonymous), do: "Anonymous requests have access to"

  defp caller_description(%{plan_name: plan_name, subscription: subscription}) do
    plan =
      [plan_name, interval(subscription), if(trialing?(subscription), do: "trial")]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    "Your plan (#{plan}) has access to"
  end

  # Users see version names, the same ones `availableVersions` returns, so the list
  # comes from the alias table. The default version is always included, even when the
  # table cannot be read.
  defp allowed_version_names(buckets) do
    [Sanbase.Metric.default_version() | VersionAlias.version_nums()]
    |> Enum.uniq()
    |> Enum.filter(&(Version.classify(&1) in buckets))
    |> Enum.sort_by(&version_sort_key/1)
    |> Enum.map_join(", ", &VersionAlias.to_version_name/1)
  end

  defp version_sort_key(version) do
    version |> String.split(".") |> Enum.map(&String.to_integer/1)
  end

  defp deny(metric, version, bucket, buckets, caller, context) do
    enforce? = enforce?()

    log_denial(
      if(enforce?, do: "Denied", else: "Would deny"),
      metric,
      version,
      bucket,
      caller,
      context
    )

    if enforce? do
      {:error,
       "Metric version #{VersionAlias.to_version_name(version)} requires " <>
         "#{@required_plan[bucket]}. #{caller_description(caller)} " <>
         "#{allowed_version_names(buckets)}."}
    else
      :ok
    end
  end

  defp exempt(metric, version, bucket, caller, context) do
    log_denial("Exempt", metric, version, bucket, caller, context)
    :ok
  end

  # Blocked calls are not exported to api_call_data (error queries never are), so this
  # line is the only record of them. key=value so Loki can aggregate with `| logfmt`.
  defp log_denial(outcome, metric, version, bucket, caller, context) do
    user = context[:auth][:current_user]

    {plan, interval, trial?} =
      case caller do
        :anonymous ->
          {"anonymous", nil, false}

        %{plan_name: plan_name, subscription: subscription} ->
          {plan_name, interval(subscription), trialing?(subscription)}
      end

    fields = [
      user_id: user && user.id,
      auth_method: context[:auth][:auth_method],
      plan: plan,
      interval: interval,
      trial: trial?,
      metric: metric,
      version: version,
      version_name: VersionAlias.to_version_name(version),
      required: bucket
    ]

    Logger.info(
      "[MetricVersionAccess] #{outcome} " <>
        Enum.map_join(fields, " ", fn {key, value} -> "#{key}=#{value}" end)
    )
  end
end
