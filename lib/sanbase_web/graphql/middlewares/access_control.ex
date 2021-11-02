defmodule SanbaseWeb.Graphql.Middlewares.AccessControl do
  @moduledoc """
  Middleware that is used to restrict the API access in a certain timeframe.

  Currently the implemented scheme is like this:
  * For users accessing data for slug `santiment` - there is no restriction.
  * If the logged in user is subscribed to a plan - the allowed historical days is the value of `historical_data_in_days`
  for this plan.
  """
  @behaviour Absinthe.Middleware

  @compile {:inline,
            transform_resolution: 1,
            check_plan: 1,
            check_from_to_params: 1,
            do_call: 2,
            restrict_from: 3,
            restrict_to: 3,
            check_from_to_both_outside: 1}

  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]

  alias Absinthe.Resolution

  alias Sanbase.Billing.{
    Subscription,
    GraphqlSchema,
    Plan,
    Plan.AccessChecker,
    Product
  }

  @freely_available_slugs ["santiment"]
  @minimal_datetime_param from_iso8601!("2009-01-01T00:00:00Z")
  @extension_metrics AccessChecker.extension_metrics()
  @extension_metric_product_map GraphqlSchema.extension_metric_product_map()

  def call(resolution, opts) do
    # First call `check_from_to_params` and then pass the execution to do_call/2
    resolution
    |> transform_resolution()
    |> check_plan()
    |> check_from_to_params()
    |> do_call(opts)
    |> check_from_to_both_outside()
  end

  # The name of the query/mutation can be passed in snake case or camel case.
  # Here we transform the name to an atom in snake case for consistency
  # and faster comparison of atoms
  defp transform_resolution(%Resolution{} = resolution) do
    %{context: context, definition: definition, arguments: arguments, source: source} = resolution

    query_atom_name =
      definition.name
      |> Macro.underscore()
      |> String.to_existing_atom()
      |> get_query_or_argument(source, arguments)

    context = context |> Map.put(:__query_argument_atom_name__, query_atom_name)

    %Resolution{resolution | context: context}
  end

  # Basic auth should have no restrictions
  defp check_plan(%Resolution{context: %{auth: %{auth_method: :basic}}} = resolution) do
    resolution
  end

  defp check_plan(%Resolution{arguments: %{slug: slug}} = resolution)
       when is_binary(slug) and slug in @freely_available_slugs do
    resolution
  end

  defp check_plan(
         %Resolution{context: %{__query_argument_atom_name__: query_or_argument} = context} =
           resolution
       ) do
    plan = context[:auth][:plan] || :free
    product = Product.code_by_id(context[:product_id]) || "SANAPI"

    case AccessChecker.plan_has_access?(plan, product, query_or_argument) do
      true ->
        resolution

      false ->
        min_plan = AccessChecker.min_plan(product, query_or_argument)
        product = String.capitalize(product)
        plan = plan |> to_string() |> String.capitalize()
        min_plan = min_plan |> to_string() |> String.capitalize()
        {argument, argument_name} = query_or_argument

        Resolution.put_result(
          resolution,
          {:error,
           """
           The #{argument} #{argument_name} is not accessible with the currently used
           #{product} #{plan} subscription. Please upgrade to #{product} #{min_plan} subscription.

           If you have a subscription for one product but attempt to fetch data using
           another product, this error will still be shown. The data on Sanbase cannot
           be fetched with a Sanapi subscription and vice versa.
           """}
        )
    end
  end

  # If the query is resolved there's nothing to do here
  # A query can get resolved if it's rejected by the AccessControl middleware
  defp do_call(%Resolution{state: :resolved} = resolution, _) do
    resolution
  end

  # If the query is marked as having free realtime and historical data
  # do not restrict anything
  defp do_call(resolution, %{allow_realtime_data: true, allow_historical_data: true}) do
    resolution
  end

  # Basic auth should have no restrictions
  defp do_call(
         %Resolution{context: %{auth: %{auth_method: :basic}}} = resolution,
         _middleware_args
       ) do
    resolution
  end

  # Allow access to historical data and real-time data for the Santiment project.
  # This will serve the purpose of showing to anonymous and users with lesser plans
  # how the data looks like.
  defp do_call(%Resolution{arguments: %{slug: slug}} = resolution, _)
       when slug in @freely_available_slugs do
    resolution
  end

  # Some specific queries/metrics are available only when a special extension is
  # present.
  defp do_call(%Resolution{context: %{__query_argument_atom_name__: query}} = resolution, _)
       when query in @extension_metrics do
    case resolution.context[:auth][:current_user] do
      %Sanbase.Accounts.User{} = user ->
        product_ids = Subscription.user_subscriptions_product_ids(user.id)

        if Map.get(@extension_metric_product_map, query) in product_ids do
          resolution
        else
          Resolution.put_result(resolution, {:error, :unauthorized})
        end

      _ ->
        Resolution.put_result(resolution, {:error, :unauthorized})
    end
  end

  # Dispatch the resolution of restricted and not-restricted queries to
  # different functions if there are `from` and `to` parameters
  defp do_call(
         %Resolution{
           context: %{__query_argument_atom_name__: query},
           arguments: %{from: _from, to: _to}
         } = resolution,
         middleware_args
       ) do
    if Plan.AccessChecker.is_restricted?(query) do
      restricted_query(resolution, middleware_args, query)
    else
      not_restricted_query(resolution, middleware_args)
    end
  end

  defp do_call(resolution, _) do
    resolution
  end

  # metrics
  defp get_query_or_argument(:timeseries_data, %{metric: metric}, _args),
    do: {:metric, metric}

  defp get_query_or_argument(:timeseries_data_per_slug, %{metric: metric}, _args),
    do: {:metric, metric}

  defp get_query_or_argument(:aggregated_timeseries_data, %{metric: metric}, _args),
    do: {:metric, metric}

  defp get_query_or_argument(:aggregated_timeseries_data, _source, %{metric: metric}),
    do: {:metric, metric}

  defp get_query_or_argument(:histogram_data, %{metric: metric}, _args),
    do: {:metric, metric}

  defp get_query_or_argument(:table_data, %{metric: metric}, _args),
    do: {:metric, metric}

  # signals
  defp get_query_or_argument(:timeseries_data, %{signal: signal}, _args),
    do: {:signal, signal}

  defp get_query_or_argument(:aggregated_timeseries_data, %{signal: signal}, _args),
    do: {:signal, signal}

  # query
  defp get_query_or_argument(query, _source, _args), do: {:query, query}

  defp restricted_query(
         %Resolution{arguments: %{from: from, to: to}, context: context} = resolution,
         middleware_args,
         query_or_argument
       ) do
    plan = context[:auth][:plan] || :free
    product_id = context[:product_id] || Product.product_api()

    historical_data_in_days =
      AccessChecker.historical_data_in_days(plan, product_id, query_or_argument)

    realtime_data_cut_off_in_days =
      AccessChecker.realtime_data_cut_off_in_days(plan, product_id, query_or_argument)

    case query_or_argument do
      {:query, _} ->
        resolution
        |> update_resolution_from_to(
          restrict_from(from, middleware_args, historical_data_in_days),
          restrict_to(to, middleware_args, realtime_data_cut_off_in_days)
        )

      _metric_or_signal ->
        resolution
        |> update_resolution_from_to(
          restrict_from(
            from,
            %{
              allow_historical_data: AccessChecker.is_historical_data_allowed?(query_or_argument)
            },
            historical_data_in_days
          ),
          restrict_to(
            to,
            %{allow_realtime_data: AccessChecker.is_realtime_data_allowed?(query_or_argument)},
            realtime_data_cut_off_in_days
          )
        )
    end
  end

  defp not_restricted_query(resolution, _middleware_args) do
    resolution
  end

  # Move the `to` datetime back so access to realtime data is not given
  defp restrict_to(to_datetime, %{allow_realtime_data: true}, _), do: to_datetime
  defp restrict_to(to_datetime, _, nil), do: to_datetime

  defp restrict_to(to_datetime, _, days) do
    restrict_to = Timex.shift(Timex.now(), days: -days)
    Enum.min_by([to_datetime, restrict_to], &DateTime.to_unix/1)
  end

  # Move the `from` datetime forward so access to historical data is not given
  defp restrict_from(from_datetime, %{allow_historical_data: true}, _), do: from_datetime
  defp restrict_from(from_datetime, _, nil), do: from_datetime

  defp restrict_from(from_datetime, _, days) when is_integer(days) do
    restrict_from = Timex.shift(Timex.now(), days: -days)
    Enum.max_by([from_datetime, restrict_from], &DateTime.to_unix/1)
  end

  defp to_param_is_after_from(from, to) do
    if DateTime.compare(to, from) == :gt do
      true
    else
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

  defp check_from_to_params(%Resolution{arguments: %{from: from, to: to}} = resolution) do
    with true <- to_param_is_after_from(from, to),
         true <- from_or_to_params_are_after_minimal_datetime(from, to) do
      resolution
    else
      {:error, _message} = error ->
        resolution
        |> Resolution.put_result(error)
    end
  end

  defp check_from_to_params(%Resolution{} = resolution), do: resolution
  defp check_from_to_both_outside(%Resolution{state: :resolved} = resolution), do: resolution

  defp check_from_to_both_outside(
         %Resolution{arguments: %{from: from, to: to}, context: context} = resolution
       ) do
    case to_param_is_after_from(from, to) do
      true ->
        resolution

      _ ->
        # If we reach here the first time we checked to < from was not true
        # This means that the middleware rewrote the params in a way that this is
        # now true. If that happens - both from and to are outside the allowed interval
        %{restricted_from: restricted_from, restricted_to: restricted_to} =
          Sanbase.Billing.Plan.Restrictions.get(
            context[:__query_argument_atom_name__],
            context[:auth][:plan] || :free,
            context[:product_id] || Product.product_api()
          )

        resolution
        |> Resolution.put_result(
          {:error,
           """
           Both `from` and `to` parameters are outside the allowed interval you can query #{context[:__query_argument_atom_name__] |> elem(1)} with your current subscription #{context[:product_id] |> Product.code_by_id()} #{context[:auth][:plan] || :free}. Upgrade to a higher tier in order to access more data.

           Allowed time restrictions:
             - `from` - #{restricted_from || "unrestricted"}
             - `to` - #{restricted_to || "unrestricted"}
           """}
        )
    end
  end

  defp check_from_to_both_outside(%Resolution{} = resolution), do: resolution

  defp update_resolution_from_to(
         %Resolution{arguments: %{from: _from, to: _to} = args} = resolution,
         from,
         to
       ) do
    %Resolution{
      resolution
      | arguments: %{
          args
          | from: from,
            to: to
        }
    }
  end
end
