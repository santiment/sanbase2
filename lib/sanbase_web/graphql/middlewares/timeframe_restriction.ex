defmodule SanbaseWeb.Graphql.Middlewares.TimeframeRestriction do
  @moduledoc """
  Middleware that is used to restrict the API access in a certain timeframe.

  Currently the implemented scheme is like this:
  * For users accessing data for slug `santiment` - there is no restriction.
  * If the user is anonymous the allowed timeframe is in the inteval [now() - 90days, now() - 1day].
  * If the user has staked 1000SAN, currently he has unlimited historical data.
  * If the logged in user is subscribed to a plan - the allowed historical days is the value of `historical_data_in_days`
  for this plan.
  """
  @behaviour Absinthe.Middleware

  @compile :inline_list_funcs
  @compile {:inline,
            restrict_from: 3,
            restrict_to: 3,
            do_call: 2,
            check_from_to_params: 1,
            check_from_to_both_outside: 1}

  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]

  alias Absinthe.Resolution
  alias Sanbase.Billing.Subscription

  @allow_access_without_staking ["santiment"]
  @minimal_datetime_param from_iso8601!("2009-01-01T00:00:00Z")
  @free_subscription Subscription.free_subscription()

  def call(resolution, opts) do
    # First call `check_from_to_params` and then pass the execution to do_call/2
    resolution
    |> check_from_to_params()
    |> do_call(opts)
    |> check_from_to_both_outside()
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

  # Allow access to historical data and real-time data for the Santiment project.
  # This will serve the purpose of showing to anonymous and users with lesser plans
  # how the data looks like.
  defp do_call(%Resolution{arguments: %{slug: slug}} = resolution, _)
       when slug in @allow_access_without_staking do
    resolution
  end

  # Basic auth should have no restrictions
  defp do_call(
         %Resolution{context: %{auth: %{auth_method: :basic}}} = resolution,
         _middleware_args
       ) do
    resolution
  end

  # Dispatch the resolution of restricted and not-restricted queries to
  # different functions if there are `from` and `to` parameters
  defp do_call(
         %Resolution{definition: definition, arguments: %{from: _from, to: _to} = args} =
           resolution,
         middleware_args
       ) do
    query =
      definition.name
      |> Macro.underscore()
      |> String.to_existing_atom()
      |> get_query(args)

    if Subscription.is_restricted?(query) do
      restricted_query(resolution, middleware_args, query)
    else
      not_restricted_query(resolution, middleware_args)
    end
  end

  defp do_call(resolution, _) do
    resolution
  end

  defp get_query(:get_metric, %{metric: metric}) do
    {:clickhouse_v2_metric, metric}
  end

  defp get_query(query, _), do: query

  defp restricted_query(
         %Resolution{arguments: %{from: from, to: to}, context: context} = resolution,
         middleware_args,
         query
       ) do
    subscription = context[:auth][:subscription] || @free_subscription
    product = subscription.plan.product_id || context.product
    historical_data_in_days = Subscription.historical_data_in_days(subscription, query, product)

    realtime_data_cut_off_in_days =
      Subscription.realtime_data_cut_off_in_days(subscription, query, product)

    resolution
    |> update_resolution_from_to(
      restrict_from(from, middleware_args, historical_data_in_days),
      restrict_to(to, middleware_args, realtime_data_cut_off_in_days)
    )
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
       The `to` datetime parameter must be after the `from` datetime parameter
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
       Cryptocurrencies didn't existed before #{@minimal_datetime_param}.
       Please check `from` and/or `to` param values.
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

  defp check_from_to_both_outside(%Resolution{arguments: %{from: from, to: to}} = resolution) do
    case to_param_is_after_from(from, to) do
      true ->
        resolution

      _ ->
        # If we reach here the first time we checked to < from was not true
        # This means that the middleware rewrote the params in a way that this is
        # now true. If that happens - both from and to are outside the allowed interval
        resolution
        |> Resolution.put_result(
          {:error,
           """
           Both `from` and `to` parameters are outside the allowed interval
           you can query with your current subscription plan.
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
