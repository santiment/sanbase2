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
            transform_resolution: 1,
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
    Product
  }

  @freely_available_slugs ["santiment"]
  @minimal_datetime_param ~U[2009-01-01 00:00:00Z]

  # Apply restrictions based on the subscription plan and query made. The check
  # is split into two main categories:
  # - When the auth method is `basic` - no restrictions are applied and only
  #   some sanity checks are done
  # - When the auth method is not `basic` - all the required checks are done
  def call(resolution, opts) do
    resolution
    |> transform_resolution()
    |> check_has_access(opts)
  end

  # The name of the query/mutation can be passed in snake case or camel case.
  # Here we transform the name to an atom in snake case for consistency
  # and faster comparison of atoms
  defp transform_resolution(%Resolution{} = resolution) do
    %{
      context: context,
      definition: definition,
      arguments: arguments,
      source: source
    } = resolution

    query_atom_name =
      definition.name
      |> Macro.underscore()
      |> String.to_existing_atom()
      |> get_query_or_argument(source, arguments)

    # Make it easier to check cases where we have either %{selector: %{slug: slug}} or just %{slug: slug}
    extracted_slug = Map.get(arguments, :slug) || get_in(arguments, [:selector, :slug])

    # Make it easier to work with the getMetric's `metric` argument,
    # so resolution.source does not need to be checked. This way it can
    # also be extracted from aggregatedTimeseriesData on a project type
    extracted_metric =
      case query_atom_name do
        {:metric, metric} -> metric
        _ -> nil
      end

    context =
      context
      |> Map.put(:__query_argument_atom_name__, query_atom_name)
      |> Map.put(:__slug__, extracted_slug)
      |> Map.put(:__metric__, extracted_metric)

    %Resolution{resolution | context: context}
  end

  # Basic auth should have no restrictions. Check only the sanity of the `from`
  # and `to` params. This includes checks that `to` is after `from` and that
  # both are after 2009-01-01T00:00:00Z.
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

  # The auth method is not `basic` and the slug is not one of the freely available slugs
  # all of the required checks are done
  defp check_has_access(resolution, opts) do
    full_check_has_access(resolution, opts)
  end

  defp full_check_has_access(resolution, opts) do
    resolution
    |> apply_if_not_resolved(&check_plan_has_access/1)
    |> apply_if_not_resolved(&check_from_to_params_sanity/1)
    |> apply_if_not_resolved(&maybe_apply_restrictions(&1, opts))
    |> apply_if_not_resolved(&check_from_to_both_outside/1)
  end

  # If a step has rejected the access, the resolution goes into a resolved
  # state so no further checks are needed. This way it can also
  # return the "most specific" error message. For example if a user does
  # not have any access to a metric it makes no sense to check the from-to
  # params and return errors for them instead of the more specific error -
  # no access for this metric because of the plan.
  defp apply_if_not_resolved(%Resolution{state: :resolved} = resolution, _) do
    resolution
  end

  defp apply_if_not_resolved(resolution, fun) do
    fun.(resolution)
  end

  # The request will be granted further access in two cases:
  # - The request contains a shared access token that has access to the
  #   query/metric. This can also be an anonymous user who has this token.
  # - The user has a subscription plan that has access to the query/metric.
  #
  # The shared access token is checked first and if it gives access to the
  # request, the user plan access is bypassed
  defp check_plan_has_access(resolution) do
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
      subscription_product: subscription_product
    } = context_to_plan_name_product_code(context)

    case AccessChecker.plan_has_access?(query_or_argument, requested_product, plan_name) do
      true ->
        resolution

      false ->
        min_plan = AccessChecker.min_plan(query_or_argument, requested_product)
        {argument, argument_name} = query_or_argument

        Resolution.put_result(
          resolution,
          {:error,
           """
           The #{argument} #{argument_name} is not accessible with the currently used \
           #{subscription_product || requested_product} #{plan_name} subscription. Please upgrade to #{requested_product} #{min_plan} subscription \
           or a Custom Plan that has access to it.

           If you have a subscription for one product but attempt to fetch data using \
           another product, this error will still be shown. The data on SANBASE cannot \
           be fetched with a SANAPI subscription and vice versa.
           """}
        )
    end
  end

  # If the query is marked as having free realtime and historical data
  # do not restrict anything
  defp maybe_apply_restrictions(resolution, %{
         allow_realtime_data: true,
         allow_historical_data: true
       }) do
    resolution
  end

  # Dispatch the resolution of restricted and not-restricted queries to
  # different functions if there are `from` and `to` parameters
  defp maybe_apply_restrictions(
         %Resolution{
           context: %{__query_argument_atom_name__: query_or_argument},
           arguments: %{from: _from, to: _to}
         } = resolution,
         middleware_args
       ) do
    if Plan.AccessChecker.is_restricted?(query_or_argument) do
      restricted_query(resolution, middleware_args, query_or_argument)
    else
      not_restricted_query(resolution, middleware_args)
    end
  end

  defp maybe_apply_restrictions(resolution, _) do
    resolution
  end

  defp restricted_query(resolution, middleware_args, query_or_argument) do
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
    # The shared access token always has an access to a closed range, so
    # full historical/realtime data is not allowed
    middleware_args = %{allow_historical_data: true, allow_realtime_data: true}

    %{
      from: from,
      to: to,
      middleware_args: middleware_args,
      historical_data_in_days: nil,
      realtime_data_cut_off_in_days: nil
    }
  end

  defp restricted_query_shared_access_token(_, _, _), do: nil

  defp restricted_query_user_plan(
         %Resolution{arguments: %{from: from, to: to}, context: context},
         middleware_args,
         query_or_argument
       ) do
    %{
      plan_name: plan_name,
      requested_product: requested_product,
      subscription_product: subscription_product
    } = context_to_plan_name_product_code(context)

    historical_data_in_days =
      AccessChecker.historical_data_in_days(
        query_or_argument,
        requested_product,
        subscription_product,
        plan_name
      )

    realtime_data_cut_off_in_days =
      AccessChecker.realtime_data_cut_off_in_days(
        query_or_argument,
        requested_product,
        subscription_product,
        plan_name
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

  defp not_restricted_query(resolution, _middleware_args) do
    resolution
  end

  # Move the `to` datetime back so access to realtime data is not given
  defp restrict_to(to_datetime, %{allow_realtime_data: true}, _),
    do: to_datetime

  defp restrict_to(to_datetime, _, nil), do: to_datetime

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
        # If we reach here the first time we checked `to < from` was not true
        # This means that the middleware rewrote the params in a way that this is
        # now true. If that happens - both from and to are outside the allowed interval
        %{
          plan_name: plan_name,
          requested_product: requested_product,
          subscription_product: subscription_product
        } = context_to_plan_name_product_code(context)

        query_or_argument = context[:__query_argument_atom_name__]

        %{restricted_from: restricted_from, restricted_to: restricted_to} =
          Sanbase.Billing.Plan.Restrictions.get(
            query_or_argument,
            requested_product,
            subscription_product,
            plan_name
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
    %Resolution{resolution | arguments: %{args | from: from, to: to}}
  end

  # metrics
  defp get_query_or_argument(:timeseries_data, %{metric: metric}, _args),
    do: {:metric, metric}

  defp get_query_or_argument(
         :timeseries_data_per_slug,
         %{metric: metric},
         _args
       ),
       do: {:metric, metric}

  defp get_query_or_argument(
         :aggregated_timeseries_data,
         %{metric: metric},
         _args
       ),
       do: {:metric, metric}

  defp get_query_or_argument(:aggregated_timeseries_data, _source, %{
         metric: metric
       }),
       do: {:metric, metric}

  defp get_query_or_argument(:histogram_data, %{metric: metric}, _args),
    do: {:metric, metric}

  defp get_query_or_argument(:table_data, %{metric: metric}, _args),
    do: {:metric, metric}

  # signals
  defp get_query_or_argument(:timeseries_data, %{signal: signal}, _args),
    do: {:signal, signal}

  defp get_query_or_argument(
         :aggregated_timeseries_data,
         %{signal: signal},
         _args
       ),
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
      subscription_product: subscription_product
    }
  end
end
