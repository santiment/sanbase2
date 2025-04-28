defmodule SanbaseWeb.Graphql.Complexity do
  alias Sanbase.Billing.Subscription

  require Logger

  @compile inline: [
             calculate_complexity: 4,
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

  def from_to_interval(args, child_complexity, struct) do
    complexity = calculate_complexity(args, child_complexity, struct, use_selector_weight: false)

    case struct do
      %{context: %{auth: %{subscription: subscription}}} when not is_nil(subscription) ->
        div(complexity, complexity_divider_number(subscription))

      _ ->
        complexity
    end
  end

  def from_to_interval_selector_weight(_, _, %{context: %{auth: %{auth_method: :basic}}}) do
    # Does not pattern match on `%Absinthe.Complexity{}` so `%Absinthe.Resolution{}`
    # can be passed. This is possible because only the context is used
    0
  end

  def from_to_interval_selector_weight(args, child_complexity, struct) do
    complexity = calculate_complexity(args, child_complexity, struct, use_selector_weight: true)

    case struct do
      %{context: %{auth: %{subscription: subscription}}} when not is_nil(subscription) ->
        div(complexity, complexity_divider_number(subscription))

      _ ->
        complexity
    end
  end

  # Private functions

  defp complexity_divider_number(%Subscription{plan: plan}) do
    case plan.name do
      "FREE" -> 1
      "BASIC" -> 4
      "ESSENTIAL" -> 4
      "PRO" -> 5
      "PRO_PLUS" -> 5
      "MAX" -> 5
      "BUSINESS_PRO" -> 6
      "BUSINESS_MAX" -> 7
      "CUSTOM" -> 7
      # TODO: Move complexity reducer to restrictions map
      "CUSTOM_" <> _ -> 7
    end
  end

  defp calculate_complexity(
         %{from: from, to: to} = args,
         child_complexity,
         struct,
         opts
       )
       when is_number(child_complexity) do
    seconds_difference = Timex.diff(from, to, :seconds) |> abs()
    years_difference_weight = years_difference_weighted(from, to)
    interval_seconds = interval_seconds(args) |> max(1)
    #
    # Struct can be Absinthe.Complexity if it is called from the complexity macro,
    # but it can also be called with Absinthe.Resolution when called from the
    # MetricResolver.timeseries_data_complexity/3 resolver function
    metric = get_metric_name(struct)

    # Compute weights
    # - child_complexity -- the number of selected fields
    # - data_points_count -- the number of data points returned
    #   The total number of fields (numbers, text, etc.) returned is
    #   child_complexity * data_points_count
    # - years_difference_weight -- if the query spans many years it means that
    #   to compute the result we need to scan more data in the database
    # - selector_weight -- in case of timeseriesDataPerSlug the number of data points
    #   depends on the number of assets/slugs. If 10 assets are provided, the data points
    #   returned will be 10 times more compared to the same query with 1 slug provided
    data_points_count = seconds_difference / interval_seconds

    selector_weight = selector_weight(args, opts)

    complexity_weight = complexity_weight(metric)

    child_complexity = if child_complexity == 0, do: 2, else: child_complexity

    [
      selector_weight,
      child_complexity,
      data_points_count,
      years_difference_weight,
      complexity_weight
    ]
    |> Enum.product()
    |> then(fn complexity ->
      if complexity > 50_000 do
        map = get_in(struct.context[:auth]) || %{}
        plan = map[:plan]
        product = map[:requested_product] || "unknown"
        user_id = (map[:current_user] || %{}) |> Map.get(:id)

        Logger.warning("""
        [Complexity] If the selector_weight #{selector_weight} is included in the complexity
        computation, the API call would have been rejected. Computed complexity is #{complexity}.
        Args: #{metric}, #{from}, #{to}, #{interval_seconds}, #{child_complexity}
        Plan: #{plan}, product: #{product}, user_id: #{user_id || "anon"}
        """)
      end

      complexity / selector_weight
    end)
    |> Sanbase.Math.to_integer()
  end

  defp complexity_weight(metric) do
    with metric when is_binary(metric) <- metric,
         weight when is_number(weight) <- Sanbase.Metric.complexity_weight(metric) do
      weight
    else
      _ -> 1
    end
  end

  @assets_count_weight 0.04
  defp selector_weight(args, opts) do
    if Keyword.get(opts, :use_selector_weight, false) do
      do_selector_weight(args)
    else
      1
    end
  end

  defp do_selector_weight(args) do
    case args do
      %{selector: %{slugs: slugs}} ->
        slugs_list_to_weight(slugs)

      %{selector: %{slug: slug_or_slugs}} ->
        # From the API the `slug` can be binary, but if it comes
        # from args_to_selector/1 it can also be a list
        List.wrap(slug_or_slugs) |> slugs_list_to_weight()

      _ ->
        # Use the process dictionary to compute and store the selector resolved result
        # in the process dictionary (can be reworked to ETS in the future).
        # Complexity checks run before any other middleware. We do some transformations
        # in the middleware and we can compute the resolved selector there and store it in
        # the context of the resolution struct, but the middleware is guaranteed to run **after**
        # the complexity check. So we need a mechanism to store the selector when it is first
        # computed in the complexity check here. The complexity macro returns just a number and
        # cannot modify the resolution struct. So we use the process dictionary.
        case Sanbase.Project.Selector.args_to_selector(args, use_process_dictionary: true) do
          {:ok, %{slug: slugs}} ->
            slugs_list_to_weight(slugs)

          _ ->
            # Most likely the selector is empty. The resolver should return a proper error
            # Put some default weight here
            1
        end
    end
  end

  defp slugs_list_to_weight(slugs) do
    Enum.max([1, length(slugs) * @assets_count_weight])
  end

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
    Timex.diff(from, to, :years) |> abs() |> max(2) |> div(2)
  end
end
