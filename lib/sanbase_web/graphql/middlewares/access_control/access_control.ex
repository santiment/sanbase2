defmodule SanbaseWeb.Graphql.Middlewares.AccessControl do
  @moduledoc """
  Middleware that is used to check and restrict the API access depending on the
  authentication method and the user's subscription plan

  Authentication is done in two major ways:
  - If the authentication is `Basic` no checks except some sanity checks are
    done
  - In case of any other authentication or no authentication, apply restrictions
    on the queried data as is described in the subscription plan or shared
    token.

  The case of authentication different than Basic is split into two main parts:
  - User authentication - the user has authenticated using their own credentials
    and the result is resolved to the user struct.
  - Shared Acecss Token authentication - shared access token is found and used
    to gain access only to some metrics/queries that are part of a chart layout.
  """
  @behaviour Absinthe.Middleware

  @compile {:inline,
            transform_resolution: 2,
            extract_selector_data: 2,
            extract_metric_and_query_data: 2,
            check_has_access: 2,
            full_check_has_access: 2,
            apply_if_not_resolved: 2,
            check_plan_has_access: 1,
            check_from_to_params_sanity: 1,
            maybe_apply_restrictions: 2,
            restrict_from: 3,
            restrict_to: 3,
            check_from_to_both_outside: 1}

  alias Absinthe.Resolution

  alias Sanbase.Billing.{
    Plan,
    Plan.AccessChecker,
    Plan.Bundle.Package,
    Plan.Bundle.PackageSnapshot,
    Product
  }

  @freely_available_slugs ["santiment"]
  @minimal_datetime_param ~U[2009-01-01 00:00:00Z]

  # Restrictions from the subscription plan and the query. Auth method `basic` gets only
  # sanity checks; every other one gets the full set.
  def call(resolution, opts) do
    resolution
    |> transform_resolution(opts)
    |> check_has_access(opts)
  end

  # The name arrives in snake or camel case; normalize to a snake case atom.
  defp transform_resolution(%Resolution{context: context} = resolution, opts) do
    context =
      context
      |> Map.merge(extract_selector_data(resolution, opts))
      |> Map.merge(extract_metric_and_query_data(resolution, opts))

    %{resolution | context: context}
  end

  defp extract_selector_data(%Absinthe.Resolution{} = resolution, _opts) do
    %{arguments: arguments} = resolution

    # Handles both %{selector: %{slug: slug}} and a bare %{slug: slug}.
    extracted_slug = Map.get(arguments, :slug) || get_in(arguments, [:selector, :slug])

    %{__slug__: extracted_slug}
  end

  defp extract_metric_and_query_data(%Absinthe.Resolution{} = resolution, _opts) do
    %{
      definition: definition,
      arguments: arguments,
      source: source
    } = resolution

    query_atom_name =
      definition.name
      |> Macro.underscore()
      |> String.to_existing_atom()
      |> get_query_or_argument(source, arguments)

    # Lifts getMetric's `metric` argument so resolution.source needs no checking, and it
    # can also be taken from aggregatedTimeseriesData on a project type.
    extracted_metric =
      case query_atom_name do
        {:metric, metric} -> metric
        _ -> nil
      end

    %{__query_argument_atom_name__: query_atom_name, __metric__: extracted_metric}
  end

  # Basic auth has no restrictions - only sanity checks on `from`/`to`: `to` after
  # `from`, both after 2009-01-01T00:00:00Z.
  defp check_has_access(
         %Resolution{context: %{auth: %{auth_method: :basic}}} = resolution,
         _opts
       ) do
    resolution
    |> check_from_to_params_sanity()
  end

  defp check_has_access(
         %Resolution{context: %{__slug__: slug}} = resolution,
         _opts
       )
       when is_binary(slug) and slug in @freely_available_slugs do
    resolution
    |> check_from_to_params_sanity()
  end

  @xrp_free_metrics_patterns [
    ~r/^transactions_count$/,
    ~r/^network_growth$/,
    ~r/^active_addresses*/,
    ~r/^holders_distribution*/,
    ~r/^dex_volume_in_(usd|xrp)*/,
    ~r/^(total|daily)_assets_issued*/,
    ~r/^(total|daily)_trustlines_count*/
  ]
  defp check_has_access(
         %Resolution{context: %{__slug__: slug, __metric__: metric}} = resolution,
         opts
       )
       when is_binary(slug) and slug in ["xrp", "ripple"] do
    cond do
      metric == nil ->
        full_check_has_access(resolution, opts)

      Enum.any?(@xrp_free_metrics_patterns, &Regex.match?(&1, metric)) ->
        resolution |> check_from_to_params_sanity()

      true ->
        full_check_has_access(resolution, opts)
    end
  end

  # Not `basic` auth and not a freely available slug - run all the checks.
  defp check_has_access(%Resolution{} = resolution, opts) do
    full_check_has_access(resolution, opts)
  end

  defp full_check_has_access(%Resolution{} = resolution, opts) do
    resolution
    |> apply_if_not_resolved(&check_experimental_metric_access/1)
    |> apply_if_not_resolved(&check_plan_has_access/1)
    |> apply_if_not_resolved(&check_from_to_params_sanity/1)
    |> apply_if_not_resolved(&maybe_apply_restrictions(&1, opts))
    |> apply_if_not_resolved(&check_from_to_both_outside/1)
  end

  # A rejecting step resolves the resolution, so no further checks run and the error stays
  # the most specific one - from-to errors are noise next to "no access to this metric".
  defp apply_if_not_resolved(%Resolution{state: :resolved} = resolution, _) do
    resolution
  end

  defp apply_if_not_resolved(%Resolution{} = resolution, fun) do
    fun.(resolution)
  end

  defp check_experimental_metric_access(
         %Resolution{context: %{__metric__: metric_name} = context} = resolution
       )
       when is_binary(metric_name) do
    user_metric_access_level =
      case context do
        %{auth: %{current_user: current_user}} -> current_user.metric_access_level
        _ -> "released"
      end

    with {:ok, metadata} <- Sanbase.Metric.metadata(metric_name),
         true <- metadata.status in ["alpha", "beta"] do
      do_check_experimental_metric(
        user_metric_access_level,
        metric_name,
        metadata.status,
        resolution
      )
    else
      _ -> resolution
    end
  end

  defp check_experimental_metric_access(%Resolution{} = resolution), do: resolution

  defp do_check_experimental_metric(
         user_metric_access_level,
         metric,
         metric_status,
         %Resolution{} = resolution
       ) do
    cond do
      user_can_access_metric?(user_metric_access_level, metric_status) ->
        resolution

      "alpha" == metric_status ->
        Resolution.put_result(
          resolution,
          {:error,
           "The metric #{metric} is currently in alpha phase and is exclusively available to alpha users."}
        )

      "beta" == metric_status ->
        Resolution.put_result(
          resolution,
          {:error,
           "The metric #{metric} is currently in beta phase and is exclusively available to alpha and beta users."}
        )

      true ->
        raise(
          ArgumentError,
          "Should not have reached here. The status is neither alpha nor beta, \
          but #{inspect(metric_status)} and the user does not have access to it."
        )
    end
  end

  defp user_can_access_metric?(user_metric_access_level, metric_status) do
    case metric_status do
      "alpha" -> user_metric_access_level == "alpha"
      "beta" -> user_metric_access_level in ["alpha", "beta"]
      _ -> false
    end
  end

  # Access comes from a shared access token covering the query/metric (its holder can be
  # anonymous) or from the user's plan. The token is checked first and bypasses the plan.
  defp check_plan_has_access(%Resolution{} = resolution) do
    case check_shared_access_token_has_access?(resolution) do
      true -> resolution
      false -> check_user_plan_has_access(resolution)
    end
  end

  defp check_shared_access_token_has_access?(%Resolution{
         arguments: arguments,
         context: %{
           __query_argument_atom_name__: query_or_argument,
           resolved_shared_access_token: token
         }
       }) do
    %{product: product_code, plan: plan_name} = token

    token_has_access? = token_has_access?(token, query_or_argument, arguments[:slug])

    plan_has_access? = AccessChecker.plan_has_access?(query_or_argument, product_code, plan_name)

    plan_has_access? and token_has_access?
  end

  defp check_shared_access_token_has_access?(%Resolution{} = _resolution),
    do: false

  defp token_has_access?(token, query_or_argument, slug) do
    case query_or_argument do
      {:metric, metric} ->
        %{metric: to_string(metric), slug: slug} in token.metrics

      {:query, query} ->
        %{query: to_string(query), slug: slug} in token.queries

      _ ->
        false
    end
  end

  defp check_user_plan_has_access(%Resolution{} = resolution) do
    %Resolution{
      context: %{__query_argument_atom_name__: query_or_argument} = context
    } = resolution

    %{
      plan_name: plan_name,
      requested_product: requested_product,
      subscription_product: subscription_product,
      entitlement: entitlement
    } = context_to_plan_name_product_code(context)

    case AccessChecker.plan_has_access?(
           query_or_argument,
           requested_product,
           plan_name,
           entitlement
         ) do
      true ->
        resolution

      false ->
        {argument, argument_name} = query_or_argument

        error_message =
          build_access_error_message(
            argument,
            argument_name,
            plan_name,
            requested_product,
            subscription_product
          )

        Resolution.put_result(resolution, {:error, error_message})
    end
  end

  defp build_access_error_message(
         argument,
         argument_name,
         "CUSTOM_" <> _ = plan_name,
         requested_product,
         subscription_product
       ) do
    """
    The #{argument} #{argument_name} is not included in the currently used \
    #{subscription_product || requested_product} #{plan_name} plan. \
    To get access, please contact Santiment to update your custom plan \
    or upgrade to a standard plan that includes it.
    """
  end

  # A bundle's access comes from the packages it bought, not the plan ladder, so `min_plan`
  # has no answer here - it told a customer paying $1050/month to "upgrade to SANAPI FREE".
  # They need the name of the package the metric is sold in.
  defp build_access_error_message(
         argument,
         argument_name,
         "BUNDLE" <> _,
         requested_product,
         subscription_product
       ) do
    product = subscription_product || requested_product

    case bundle_packages_for(argument, argument_name) do
      [] ->
        """
        The #{argument} #{argument_name} is not included in your #{product} bundle. \
        It is not part of any package that is currently sold - please contact Santiment.
        """

      slugs ->
        """
        The #{argument} #{argument_name} is not included in your #{product} bundle. \
        It is part of #{packages_phrase(slugs)} - add it with the addBundleItem \
        mutation, or contact Santiment.
        """
    end
  end

  defp build_access_error_message(
         argument,
         argument_name,
         plan_name,
         requested_product,
         subscription_product
       ) do
    min_plan = AccessChecker.min_plan({argument, argument_name}, requested_product)

    """
    The #{argument} #{argument_name} is not accessible with the currently used \
    #{subscription_product || requested_product} #{plan_name} subscription. Please upgrade to #{requested_product} #{min_plan} subscription \
    or a Custom Plan that has access to it.

    If you have a subscription for one product but attempt to fetch data using \
    another product, this error will still be shown. The data on SANBASE cannot \
    be fetched with a SANAPI subscription and vice versa.
    """
  end

  # Only metrics are sold in packages. Queries and signals reach here too (every bundle
  # gets all of them, so a refusal is unexpected rather than impossible) and are matched
  # out rather than looked up: a name coinciding with a metric would name a wrong package.
  defp bundle_packages_for(:metric, metric_name),
    do: PackageSnapshot.packages_containing(metric_name)

  defp bundle_packages_for(_argument, _argument_name), do: []

  # "the Development Data package" / "the Market Data and On-chain Labels packages"
  defp packages_phrase([slug]), do: "the #{package_name(slug)} package"

  defp packages_phrase(slugs) do
    {rest, [last]} = slugs |> Enum.map(&package_name/1) |> Enum.split(-1)

    "the #{Enum.join(rest, ", ")} and #{last} packages"
  end

  # `by_slug/1` cannot fail on a slug from `packages_containing/1`. The error branch is
  # there because a CaseClauseError here would hide the refusal it explains.
  defp package_name(slug) do
    case Package.by_slug(slug) do
      {:ok, %{name: name}} -> name
      {:error, _reason} -> slug
    end
  end

  # Queries marked as free realtime and historical are not restricted.
  defp maybe_apply_restrictions(%Resolution{} = resolution, %{
         allow_realtime_data: true,
         allow_historical_data: true
       }) do
    resolution
  end

  # With `from` and `to` present, restricted and unrestricted queries take different paths.
  defp maybe_apply_restrictions(
         %Resolution{
           context: %{__query_argument_atom_name__: query_or_argument},
           arguments: %{from: _from, to: _to}
         } = resolution,
         middleware_args
       ) do
    if Plan.AccessChecker.restricted?(query_or_argument) do
      restricted_query(resolution, middleware_args, query_or_argument)
    else
      not_restricted_query(resolution, middleware_args)
    end
  end

  defp maybe_apply_restrictions(%Resolution{} = resolution, _) do
    resolution
  end

  defp restricted_query(%Resolution{} = resolution, middleware_args, query_or_argument) do
    args =
      case restricted_query_shared_access_token(
             resolution,
             middleware_args,
             query_or_argument
           ) do
        nil ->
          restricted_query_user_plan(
            resolution,
            middleware_args,
            query_or_argument
          )

        args ->
          args
      end

    %{
      from: from,
      to: to,
      middleware_args: middleware_args,
      historical_data_in_days: historical_data_in_days,
      realtime_data_cut_off_in_days: realtime_data_cut_off_in_days
    } = args

    resolution
    |> update_resolution_from_to(
      restrict_from(from, middleware_args, historical_data_in_days),
      restrict_to(to, middleware_args, realtime_data_cut_off_in_days)
    )
  end

  defp restricted_query_shared_access_token(
         %Resolution{
           arguments: %{from: from, to: to},
           context: %{
             __query_argument_atom_name__: query_or_argument,
             resolved_shared_access_token: _token
           }
         },
         _middleware_args,
         query_or_argument
       ) do
    # A shared access token grants a closed range, never full history or realtime.
    middleware_args = %{allow_historical_data: true, allow_realtime_data: true}

    %{
      from: from,
      to: to,
      middleware_args: middleware_args,
      historical_data_in_days: nil,
      realtime_data_cut_off_in_days: nil
    }
  end

  defp restricted_query_shared_access_token(%Resolution{} = _, _, _), do: nil

  defp restricted_query_user_plan(
         %Resolution{arguments: %{from: from, to: to}, context: context},
         middleware_args,
         query_or_argument
       ) do
    %{
      plan_name: plan_name,
      requested_product: requested_product,
      subscription_product: subscription_product,
      entitlement: entitlement
    } = context_to_plan_name_product_code(context)

    historical_data_in_days =
      AccessChecker.historical_data_in_days(
        query_or_argument,
        requested_product,
        subscription_product,
        plan_name,
        entitlement
      )

    realtime_data_cut_off_in_days =
      AccessChecker.realtime_data_cut_off_in_days(
        query_or_argument,
        requested_product,
        subscription_product,
        plan_name,
        entitlement
      )

    case query_or_argument do
      {:query, _} ->
        %{
          from: from,
          to: to,
          middleware_args: middleware_args,
          historical_data_in_days: historical_data_in_days,
          realtime_data_cut_off_in_days: realtime_data_cut_off_in_days
        }

      # metric or signal
      {_, _} ->
        middleware_args = %{
          allow_historical_data:
            AccessChecker.historical_data_freely_available?(query_or_argument),
          allow_realtime_data: AccessChecker.realtime_data_freely_available?(query_or_argument)
        }

        %{
          from: from,
          to: to,
          middleware_args: middleware_args,
          historical_data_in_days: historical_data_in_days,
          realtime_data_cut_off_in_days: realtime_data_cut_off_in_days
        }
    end
  end

  defp not_restricted_query(%Resolution{} = resolution, _middleware_args) do
    resolution
  end

  # Move the `to` datetime back so access to realtime data is not given
  defp restrict_to(to_datetime, %{allow_realtime_data: true}, _),
    do: to_datetime

  defp restrict_to(to_datetime, _, nil), do: to_datetime
  defp restrict_to(to_datetime, _, 0), do: to_datetime

  defp restrict_to(to_datetime, _, days) do
    restrict_to = Timex.shift(Timex.now(), days: -days)
    Enum.min_by([to_datetime, restrict_to], &DateTime.to_unix/1)
  end

  # Move the `from` datetime forward so access to historical data is not given
  defp restrict_from(from_datetime, %{allow_historical_data: true}, _),
    do: from_datetime

  defp restrict_from(from_datetime, _, nil), do: from_datetime

  defp restrict_from(from_datetime, _, days) when is_integer(days) do
    restrict_from = Timex.shift(Timex.now(), days: -days)
    Enum.max_by([from_datetime, restrict_from], &DateTime.to_unix/1)
  end

  defp to_param_is_after_from(from, to) do
    case DateTime.compare(to, from) do
      :gt ->
        true

      _ ->
        {:error,
         """
         The `to` datetime parameter must be after the `from` datetime parameter.
         """}
    end
  end

  defp from_or_to_params_are_after_minimal_datetime(from, to) do
    if DateTime.compare(from, @minimal_datetime_param) == :gt and
         DateTime.compare(to, @minimal_datetime_param) == :gt do
      true
    else
      {:error,
       """
       Cryptocurrencies didn't exist before #{@minimal_datetime_param}.
       Please check `from` and/or `to` parameters values.
       """}
    end
  end

  defp check_from_to_params_sanity(%Resolution{arguments: %{from: from, to: to}} = resolution) do
    with true <- to_param_is_after_from(from, to),
         true <- from_or_to_params_are_after_minimal_datetime(from, to) do
      resolution
    else
      {:error, _message} = error ->
        resolution
        |> Resolution.put_result(error)
    end
  end

  defp check_from_to_params_sanity(%Resolution{} = resolution), do: resolution

  defp check_from_to_both_outside(
         %Resolution{arguments: %{from: from, to: to}, context: context} = resolution
       ) do
    case to_param_is_after_from(from, to) do
      true ->
        resolution

      _ ->
        # `to < from` was false on the first check, so the middleware rewrote the params
        # into it - which means both are outside the allowed interval.
        %{
          plan_name: plan_name,
          requested_product: requested_product,
          subscription_product: subscription_product,
          entitlement: entitlement
        } = context_to_plan_name_product_code(context)

        query_or_argument = context[:__query_argument_atom_name__]

        %{restricted_from: restricted_from, restricted_to: restricted_to} =
          Sanbase.Billing.Plan.Restrictions.get(
            query_or_argument,
            requested_product,
            subscription_product,
            plan_name,
            entitlement
          )

        resolution
        |> Resolution.put_result(
          {:error,
           """
           Both `from` and `to` parameters are outside the allowed interval you can query \
           #{query_or_argument |> elem(1)} with your current subscription #{subscription_product || requested_product} #{plan_name}. \
           Upgrade to a higher tier in order to access more data.

           Allowed time restrictions:
             - `from` - #{restricted_from || "unrestricted"}
             - `to` - #{restricted_to || "unrestricted"}
           """}
        )
    end
  end

  defp check_from_to_both_outside(%Resolution{} = resolution), do: resolution

  defp update_resolution_from_to(
         %Resolution{arguments: args} = resolution,
         from,
         to
       ) do
    %{resolution | arguments: %{args | from: from, to: to}}
  end

  # metrics
  @get_metric_fields [
    :aggregated_timeseries_data,
    :timeseries_data,
    :timeseries_data_json,
    :timeseries_data_per_slug,
    :timeseries_data_per_slug_json,
    :table_data,
    :histogram_data
  ]
  defp get_query_or_argument(field, %{metric: metric}, _args) when field in @get_metric_fields,
    do: {:metric, metric}

  defp get_query_or_argument(:aggregated_timeseries_data, _source, %{metric: metric}),
    do: {:metric, metric}

  # signals
  defp get_query_or_argument(:timeseries_data, %{signal: signal}, _args),
    do: {:signal, signal}

  # hyperliquid BBO prices — nested under `hyperliquidBboPrices`
  defp get_query_or_argument(:timeseries_data, %{__source__: :hyperliquid_bbo_prices}, _args),
    do: {:query, :hyperliquid_bbo_prices}

  defp get_query_or_argument(:aggregated_timeseries_data, %{signal: signal}, _args),
    do: {:signal, signal}

  # query
  defp get_query_or_argument(query, _source, _args), do: {:query, query}

  defp context_to_plan_name_product_code(context) do
    plan_name = context[:auth][:plan] || "FREE"
    requested_product_id = context[:requested_product_id] || Product.product_api()
    requested_product = Product.code_by_id(requested_product_id)
    subscription_product_id = context[:subscription_product_id]
    subscription_product = Product.code_by_id(subscription_product_id)

    %{
      plan_name: plan_name,
      requested_product: requested_product,
      subscription_product: subscription_product,
      entitlement: bundle_entitlement(context)
    }
  end

  # Only bundle plans read this. Every bundle subscription is named `BUNDLE`, so the plan
  # name identifies nothing and what the customer bought has to travel with the request.
  # `auth_plug.ex` puts the subscription in the context; this keeps it from being dropped
  # on the way to the access checker. See §5.8 of docs/composable-api-plans-handover.md.
  defp bundle_entitlement(context),
    do: Sanbase.Billing.Subscription.bundle_entitlement(context[:auth][:subscription])
end
