defmodule SanbaseWeb.Graphql.Complexity do
  require Logger

  @compile inline: [
             calculate_complexity: 3,
             interval_seconds: 1,
             years_difference_weighted: 2,
             get_metric_name: 1
           ]
  @doc ~S"""
  Returns the complexity as a real number.

  For basic authorization:
    Internal services use basic authentication. Return complexity = 0 to allow them
    to access everything without limits.

  For apikey/jwt/anon authorized users:
    Returns the complexity of the query. It is the number of intervals in the period
    'from-to' multiplied by the child complexity. The child complexity is the number
    of fields that will be returned for a single price point. The calculation is done
    based only on the supplied arguments and avoids accessing the DB if the query
    is rejected.
  """

  def from_to_interval(_, _, %{context: %{auth: %{auth_method: :basic}}}) do
    # Does not pattern match on `%Absinthe.Complexity{}` so `%Absinthe.Resolution{}`
    # can be passed. This is possible because only the context is used
    0
  end

  def from_to_interval(
        args,
        child_complexity,
        %{context: %{auth: %{subscription: subscription}}} = struct
      )
      when not is_nil(subscription) do
    complexity = calculate_complexity(args, child_complexity, struct)

    case Sanbase.Billing.Plan.plan_name(subscription.plan) do
      "FREE" -> complexity
      "BASIC" -> div(complexity, 4)
      "PRO" -> div(complexity, 5)
      "PRO_PLUS" -> div(complexity, 5)
      "PREMIUM" -> div(complexity, 6)
      "CUSTOM" -> div(complexity, 7)
      # TODO: Move complexity reducer to restrictions map
      "CUSTOM_" <> _ -> div(complexity, 7)
    end
  end

  def from_to_interval(%{} = args, child_complexity, struct) do
    calculate_complexity(args, child_complexity, struct)
  end

  def from_to_interval_per_slug(args, child_complexity, struct) do
    many_slugs_weight = many_slugs_weight(args)

    many_slugs_weight * from_to_interval(args, child_complexity, struct)
  end

  # Private functions

  defp calculate_complexity(%{from: from, to: to} = args, child_complexity, struct) do
    seconds_difference = Timex.diff(from, to, :seconds) |> abs
    years_difference_weighted = years_difference_weighted(from, to)
    interval_seconds = interval_seconds(args) |> max(1)
    metric = get_metric_name(struct)

    complexity_weight =
      with metric when is_binary(metric) <- metric,
           weight when is_number(weight) <- Sanbase.Metric.complexity_weight(metric) do
        weight
      else
        _ -> 1
      end

    (child_complexity * (seconds_difference / interval_seconds) * years_difference_weighted *
       complexity_weight)
    |> Sanbase.Math.to_integer()
  end

  defp many_slugs_weight(%{selector: %{slugs: slugs}}) when is_list(slugs), do: length(slugs)
  defp many_slugs_weight(args), do: 1

  # This case is important as here the flow comes from `timeseries_data_complexity`
  # and it will be handled by extracting the name from the %Absinthe.Resolution{}
  # struct manually passed. This is done because otherwise the same `getMetric`
  # resolution flow could pass twice through this code and remove 2 metrics instead
  # of just one. This happens if both timeseries_data and timeseries_data_complexity
  # are queried
  defp get_metric_name(%{source: %{metric: metric}}), do: metric

  defp get_metric_name(_) do
    case Process.get(:__metric_name_from_get_metric_api__) do
      [metric | rest] ->
        # If there are batched requests they will be resolved in the same order
        # as their are in the list. When computing complexity for a metric put back
        # the list without this one metric so the next one can be properly fetched.
        Process.put(:__metric_name_from_get_metric_api__, rest)
        metric

      _ ->
        nil
    end
  end

  defp interval_seconds(args) do
    case Map.get(args, :interval, "") do
      "" -> "1d"
      interval -> interval
    end
    |> Sanbase.DateTimeUtils.str_to_sec()
  end

  defp years_difference_weighted(from, to) do
    Timex.diff(from, to, :years) |> abs |> max(2) |> div(2)
  end
end
