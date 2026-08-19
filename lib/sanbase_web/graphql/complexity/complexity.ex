defmodule SanbaseWeb.Graphql.Complexity do
  alias Sanbase.Billing.Plan
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

  # No catch-all on purpose - an unknown plan fails loudly instead of silently getting
  # FREE-tier complexity. A bundle resolves to its equivalent standard plan first: query
  # cost has nothing to do with the packages bought, and every bundle is named `BUNDLE`.
  defp complexity_divider_number(%Subscription{plan: plan}) do
    case Plan.type(plan.name) do
      :bundle -> divider_for_plan_name(Sanbase.Billing.Plan.Bundle.equivalent_standard_plan())
      _ -> divider_for_plan_name(plan.name)
    end
  end

  defp divider_for_plan_name(plan_name) do
    case plan_name do
      "FREE" -> 1
      "BASIC" -> 4
      "ESSENTIAL" -> 4
      "PRO" -> 5
      "PRO_PLUS" -> 5
      "MAX" -> 5
      "BUSINESS_PRO" -> 6
      "BUSINESS_MAX" -> 7
      "INSTITUTIONAL" -> 7
      "ENTERPRISE" -> 7
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
    # Absinthe.Complexity when called from the complexity macro, Absinthe.Resolution
    # when called from MetricResolver.timeseries_data_complexity/3.
    metric = get_metric_name(struct)

    # Weights: child_complexity (selected fields), data_points_count,
    # years_difference_weight (a long span scans more data) and selector_weight
    # (timeseriesDataPerSlug returns 10x the points for 10 assets).
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
      plan = get_in(struct.context, [:auth, :plan])

      if complexity > 50_000 and selector_weight > 1 and plan != "FREE" do
        map = get_in(struct.context[:auth]) || %{}
        plan = map[:plan]
        product = map[:requested_product] || "unknown"
        user_id = (map[:current_user] || %{}) |> Map.get(:id)

        Logger.warning("""
        [ComplexityRestriction] A user's query has exceeded the complexity limit and is: #{complexity}
        Selector weight: #{selector_weight}. Complexity without selector weight: #{complexity / selector_weight}
        Args: metric: #{metric}, from: #{from}, to: #{to}, interval (in seconds) #{interval_seconds}, child_complexity: #{child_complexity}
        Plan: #{plan}, product: #{product}, user_id: #{user_id || "anon"}
        """)
      end

      complexity
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

  @assets_count_weight 0.1
  defp selector_weight(args, opts) do
    if Keyword.get(opts, :use_selector_weight, false) do
      do_selector_weight(args)
    else
      1
    end
  end

  defp do_selector_weight(args) do
    # Number of slugs times @assets_count_weight. Could be superlinear instead, e.g.
    # 0.1*x + 0.001*x*x.
    case args do
      %{selector: %{slugs: slugs}} ->
        slugs_list_to_weight(slugs)

      %{selector: %{slug: slug_or_slugs}} ->
        # A binary from the API, a list when it comes from args_to_selector/1.
        List.wrap(slug_or_slugs) |> slugs_list_to_weight()

      _ ->
        # The complexity check runs BEFORE every middleware and returns just a number, so
        # the resolved selector goes to the process dictionary for the middleware to reuse.
        case Sanbase.Project.Selector.args_to_selector(args, use_process_dictionary: true) do
          {:ok, %{slug: slugs}} ->
            slugs_list_to_weight(slugs)

          _ ->
            # Most likely an empty selector - the resolver returns the proper error.
            1
        end
    end
  end

  defp slugs_list_to_weight(slugs) do
    Enum.max([1, length(slugs) * @assets_count_weight])
  end

  # The name comes from the manually passed %Absinthe.Resolution{}, or one `getMetric`
  # resolution would pass here twice and remove two metrics.
  defp get_metric_name(%{source: %{metric: metric}}), do: metric

  defp get_metric_name(_) do
    case Process.get(:__metric_name_from_get_metric_api__) do
      [metric | rest] ->
        # Batched requests resolve in list order, so put the list back without this
        # metric and the next one is fetched correctly.
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
    |> Sanbase.Utils.DateTime.str_to_sec()
  end

  defp years_difference_weighted(from, to) do
    Timex.diff(from, to, :years) |> abs() |> max(2) |> div(2)
  end
end
