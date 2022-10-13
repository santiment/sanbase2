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

  defp get_plan("CUSTOM_" <> _ = plan_name, product_code) do
    product_id = Sanbase.Billing.Product.id_by_code(product_code)

    plan =
      from(p in Plan,
        where:
          p.name == ^plan_name and p.product_id == ^product_id and
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
    %{
      "accessible" => accessible,
      "not_accessible" => not_accessible,
      "not_accessible_patterns" => not_accessible_patterns
    } = access_map

    accessible =
      case accessible do
        "all" ->
          get_all_function.()

        _ ->
          accessible
      end

    not_accessible_by_pattern =
      get_not_accessible_by_patterns(accessible, not_accessible_patterns)

    accessible -- (not_accessible ++ not_accessible_by_pattern)
  end

  # From the accessible list, return those which are not accessible because they
  # match one of the provided patterns.
  # Example: If all MVRV metrics need to be excluded, instead of listing them all
  # one by one, the pattern "mvrv_" can be provided
  defp get_not_accessible_by_patterns(list, patterns) do
    regex_list = Enum.map(patterns, &Regex.compile!/1)

    Enum.filter(list, fn elem ->
      Enum.any?(regex_list, fn regex -> String.match?(elem, regex) end)
    end)
  end
end
