defmodule Sanbase.Billing.Plan.Restrictions do
  @moduledoc ~s"""
  Work with the access restrictions for all queries and metrics.
  A time restrictions is defined by the query/metric, plan and product.
  """

  alias Sanbase.Billing.{Product, Plan.AccessChecker}

  @type restriction :: %{
          type: String.t(),
          name: String.t(),
          is_accessible: boolean(),
          is_restricted: boolean(),
          restricted_from: DateTime.t(),
          restricted_to: DateTime.t()
        }

  @spec get(query_or_metric, atom(), non_neg_integer()) :: restriction()
        when query_or_metric: {:metric, String.t()} | {:query, atom()}
  def get({type, name} = query_or_metric, plan, product_id)
      when type in [:metric, :query] do
    type_str = type |> to_string()
    name_str = construct_name(type, name)
    product = Product.code_by_id(product_id)

    case AccessChecker.plan_has_access?(plan, product, query_or_metric) do
      false ->
        no_access_map(type_str, name_str)

      true ->
        case AccessChecker.is_restricted?(query_or_metric) do
          false ->
            not_restricted_access_map(type_str, name_str)

          true ->
            maybe_restricted_access_map(type_str, name_str, plan, product_id, query_or_metric)
        end
    end
  end

  @doc ~s"""
  Return a list in which every element describes either a metric or a query.
  The elements are maps describing the time restrictions of the given metric/query.
  """
  @spec get_all(atom(), non_neg_integer()) :: list(restriction)
  def get_all(plan, product_id) do
    metrics = Sanbase.Metric.available_metrics() |> Enum.map(&{:metric, &1})

    queries =
      Sanbase.Model.Project.AvailableQueries.all_atom_names()
      |> Enum.map(&{:query, &1})

    # elements are {:metric, <string>} or {:query, <atom>}
    result =
      (queries ++ metrics)
      |> Enum.map(fn metric_or_query -> get(metric_or_query, plan, product_id) end)

    (get_extra_queries(plan, product_id) ++ result)
    |> Enum.filter(& &1.is_accessible)
    |> Enum.uniq_by(& &1.name)
    |> Enum.sort_by(& &1.name)
  end

  # Private functions

  defp no_access_map(type_str, name_str) do
    %{
      type: type_str,
      name: name_str,
      min_interval: min_interval(type_str, name_str),
      is_accessible: false,
      is_restricted: false,
      restricted_from: nil,
      restricted_to: nil
    }
  end

  defp not_restricted_access_map(type_str, name_str) do
    %{
      type: type_str,
      name: name_str,
      min_interval: min_interval(type_str, name_str),
      is_accessible: true,
      is_restricted: false
    }
  end

  defp maybe_restricted_access_map(type_str, name_str, plan, product_id, query_or_metric) do
    now = Timex.now()

    restricted_from =
      case AccessChecker.historical_data_in_days(plan, product_id, query_or_metric) do
        nil -> nil
        days -> Timex.shift(now, days: -days)
      end

    restricted_to =
      case AccessChecker.realtime_data_cut_off_in_days(plan, product_id, query_or_metric) do
        nil -> nil
        0 -> nil
        days -> Timex.shift(now, days: -days)
      end

    %{
      type: type_str,
      name: name_str,
      min_interval: min_interval(type_str, name_str),
      is_accessible: true,
      is_restricted: not is_nil(restricted_from) or not is_nil(restricted_to),
      restricted_from: restricted_from,
      restricted_to: restricted_to
    }
  end

  defp construct_name(:metric, name), do: name |> to_string()
  defp construct_name(:query, name), do: name |> Inflex.camelize(:lower)

  defp min_interval("metric", metric) do
    {:ok, metadata} = Sanbase.Metric.metadata(metric)
    metadata.min_interval
  end

  defp min_interval("query", query)
       when query in [
              "dailyActiveDeposits",
              "miningPoolsDistribution",
              "historyTwitterData",
              "percentOfTokenSupplyOnExchanges"
            ],
       do: "1d"

  defp min_interval("query", query)
       when query in [
              "gasUsed",
              "devActivity",
              "githubActivity",
              "historicalBalance",
              "historyPrice",
              "priceVolumeDiff",
              "socialDominance",
              "githubActivity",
              "minersBalance",
              "ohlc",
              "getProjectTrendingHistory",
              "ethSpentOverTime"
            ],
       do: "5m"

  defp min_interval("query", _query), do: nil

  defp get_extra_queries(_plan, _product_id) do
    [not_restricted_access_map("query", "ethSpentOverTime")]
  end
end
