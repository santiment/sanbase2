defmodule Sanbase.Billing.Plan.MetricVersionAccess do
  @moduledoc ~s"""
  Decides whether a GraphQL request may use a given metric version.

  Only SanAPI requests are restricted: apikey calls and anonymous calls that do not
  come from a Santiment origin. Sanbase (JWT, Sansheets, Santiment-origin anonymous)
  and basic auth are never restricted. The entitlement matrix lives in
  `Sanbase.Billing.Plan.ApiAccessChecker.metric_version_buckets/4`.

  Enforcement is behind the `:enforce` flag (`METRIC_VERSION_ACCESS_ENFORCE`). While it
  is off, a request that would be denied is logged and then allowed, so the impact can
  be measured before any customer loses access.
  """

  require Logger

  alias Sanbase.Billing.Plan.AccessChecker
  alias Sanbase.Billing.Product
  alias Sanbase.Metric.Version
  alias Sanbase.Metric.VersionAlias

  @required_plan %{
    standard: "a SanAPI Business Pro or Business Max subscription",
    pit: "a paid yearly SanAPI Business Max subscription"
  }

  @spec check(String.t(), String.t(), map()) :: :ok | {:error, String.t()}
  def check(metric, version, context) do
    bucket = bucket(version)

    case allowed_buckets(context) do
      :all ->
        :ok

      buckets ->
        if bucket in buckets, do: :ok, else: deny(metric, version, bucket, buckets, context)
    end
  end

  @doc false
  def enforce?() do
    Sanbase.Utils.Config.module_get_boolean(__MODULE__, :enforce) == true
  end

  # A non-numeric version that is not Experimental (those have their own rule and
  # never reach here) is treated as the most restricted bucket.
  defp bucket(version) do
    case Version.classify(version) do
      :other -> :pit
      bucket -> bucket
    end
  end

  defp allowed_buckets(%{auth: %{auth_method: :basic}}), do: :all

  defp allowed_buckets(%{requested_product_id: product_id} = context)
       when is_integer(product_id) do
    %{plan_name: plan_name, interval: interval, trialing?: trialing?} = subscription_info(context)

    AccessChecker.metric_version_buckets(
      Product.code_by_id(product_id),
      Product.code_by_id(context[:subscription_product_id]),
      plan_name,
      interval,
      trialing?
    )
  end

  # No resolved product means the request did not go through the auth plug (an
  # internal call), which is not something this restriction is about.
  defp allowed_buckets(_context), do: :all

  defp subscription_info(context) do
    subscription = context[:auth][:subscription]

    %{
      plan_name: context[:auth][:plan] || "FREE",
      interval: get_in(subscription, [Access.key(:plan), Access.key(:interval)]),
      trialing?: match?(%{status: :trialing}, subscription)
    }
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

  defp deny(metric, version, bucket, buckets, context) do
    %{plan_name: plan_name, interval: interval, trialing?: trialing?} = subscription_info(context)

    plan_description =
      [plan_name, interval, if(trialing?, do: "trial")]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    message =
      "Metric version #{VersionAlias.to_version_name(version)} requires " <>
        "#{@required_plan[bucket]}. Your plan (#{plan_description}) has access to " <>
        "#{allowed_version_names(buckets)}."

    if enforce?() do
      {:error, message}
    else
      Logger.info(
        "[MetricVersionAccess] Would deny metric #{metric} version #{version} " <>
          "for user_id=#{inspect(context[:auth][:current_user] && context[:auth][:current_user].id)} " <>
          "auth_method=#{inspect(context[:auth][:auth_method])} plan=#{plan_description}"
      )

      :ok
    end
  end
end
