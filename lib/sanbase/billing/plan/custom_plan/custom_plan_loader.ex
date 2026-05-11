defmodule Sanbase.Billing.Plan.CustomPlan.Loader do
  @moduledoc ~s"""
  Load custom plans from the database and stored them in :persistent_term
  """

  import Ecto.Query

  alias Sanbase.Billing.{Plan, Plan.CustomPlan}
  alias Sanbase.Billing.ApiInfo

  @doc ~s"""
  The plans restrictions are chcked on every request, so they need to have
  constant access. Once the restrictions are stored for a plan, they are not
  updated.
  """
  def get_data(plan_name, product_code) do
    case :persistent_term.get({__MODULE__, plan_name, product_code}, :plan_not_stored) do
      :plan_not_stored ->
        {:ok, %Plan{restrictions: restrictions}} = get_plan(plan_name, product_code)

        data = %{
          restrictions: restrictions,
          resolved_metrics: resolve_metrics(restrictions),
          resolved_queries: resolve_queries(restrictions),
          resolved_signals: resolve_signals(restrictions)
        }

        :ok = put_data(plan_name, product_code, data)

        data

      data ->
        data
    end
  end

  def put_plans_in_persistent_term() do
    plans =
      from(p in Plan,
        where: p.has_custom_restrictions == true
      )
      |> Sanbase.Repo.all()
      # There are montly and yearly plans, both should have the same plan
      |> Enum.uniq_by(&{&1.name, &1.product_id})

    for %{name: plan_name, restrictions: restrictions, product_id: product_id} <- plans do
      data = %{
        restrictions: restrictions,
        resolved_metrics: resolve_metrics(restrictions),
        resolved_queries: resolve_queries(restrictions),
        resolved_signals: resolve_signals(restrictions)
      }

      product_code = Sanbase.Billing.Product.code_by_id(product_id)

      put_data(plan_name, product_code, data)
    end
  end

  defp get_plan("CUSTOM_" <> _ = plan_name, _product_code) do
    plan =
      from(p in Plan,
        where:
          p.name == ^plan_name and
            p.has_custom_restrictions == true,
        # There are montly and yearly plans, both should have the same plan
        limit: 1
      )
      |> Sanbase.Repo.one()

    case plan do
      nil -> {:error, "Missing plan #{plan_name}"}
      plan -> {:ok, plan}
    end
  end

  defp put_data(plan_name, product_code, data) do
    :persistent_term.put({__MODULE__, plan_name, product_code}, data)
  end

  defp resolve_metrics(%CustomPlan.Restrictions{} = restrictions) do
    %{metric_access: access_map} = restrictions

    get_all_function = fn ->
      Sanbase.Metric.free_metrics() ++ Sanbase.Metric.restricted_metrics()
    end

    resolve_accessible_list(access_map, get_all_function)
  end

  defp resolve_queries(%CustomPlan.Restrictions{} = restrictions) do
    %{query_access: access_map} = restrictions

    get_all_function = fn ->
      (ApiInfo.get_queries_with_access_level(:free) ++
         ApiInfo.get_queries_with_access_level(:restricted))
      |> Enum.map(&Atom.to_string/1)
    end

    resolve_accessible_list(access_map, get_all_function)
  end

  defp resolve_signals(%CustomPlan.Restrictions{} = restrictions) do
    %{signal_access: access_map} = restrictions

    get_all_function = fn ->
      Sanbase.Signal.free_signals() ++ Sanbase.Signal.restricted_signals()
    end

    resolve_accessible_list(access_map, get_all_function)
  end

  defp resolve_accessible_list(access_map, get_all_function) do
    accessible = Map.get(access_map, "accessible", [])
    accessible_patterns = Map.get(access_map, "accessible_patterns", [])
    not_accessible = Map.get(access_map, "not_accessible", [])
    not_accessible_patterns = Map.get(access_map, "not_accessible_patterns", [])

    all_items = get_all_function.()

    # Step 1: Build the accessible list from explicit items + pattern matches
    accessible_list =
      case accessible do
        "all" ->
          all_items

        list when is_list(list) ->
          accessible_by_pattern = get_matching_by_patterns(all_items, accessible_patterns)
          Enum.uniq(list ++ accessible_by_pattern)
      end

    # Step 2: Remove not_accessible items (not_accessible has HIGHER priority)
    not_accessible_list =
      case not_accessible do
        "all" -> all_items
        list when is_list(list) -> list
      end

    not_accessible_by_pattern = get_matching_by_patterns(accessible_list, not_accessible_patterns)

    accessible_list -- (not_accessible_list ++ not_accessible_by_pattern)
  end

  # From the given list, return those items that match at least one of the
  # provided regex patterns.
  # Example: pattern "mvrv_" matches all MVRV metrics; pattern "^social_"
  # matches all metrics starting with "social_".
  defp get_matching_by_patterns(_list, []), do: []

  defp get_matching_by_patterns(list, patterns) do
    regex_list = Enum.map(patterns, &Regex.compile!/1)

    Enum.filter(list, fn elem ->
      Enum.any?(regex_list, fn regex -> String.match?(elem, regex) end)
    end)
  end
end
