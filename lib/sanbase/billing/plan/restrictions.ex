defmodule Sanbase.Billing.Plan.Restrictions do
  @moduledoc ~s"""
  Work with the access restrictions for all queries and metrics.
  A time restrictions is defined by the query/metric, plan and product.
  """

  alias Sanbase.Billing.Plan.AccessChecker

  @type restriction :: %{
          type: String.t(),
          name: String.t(),
          human_readable_name: String.t(),
          internal_name: String.t(),
          min_interval: String.t(),
          is_accessible: boolean(),
          is_restricted: boolean(),
          restricted_from: DateTime.t() | nil,
          restricted_to: DateTime.t() | nil,
          is_deprecated: boolean(),
          hard_deprecate_after: DateTime.t() | nil,
          docs: list(String.t()),
          available_selectors: list(atom()),
          required_selectors: list(list(atom()))
        }

  @type query_or_argument :: {:metric, String.t()} | {:signal, String.t()} | {:query, atom()}
  @spec get(query_or_argument, String.t(), String.t(), String.t()) :: restriction()
  def get({type, name} = query_or_argument, requested_product, subscription_product, plan_name)
      when type in [:metric, :signal, :query] do
    type_str = to_string(type)
    name_str = construct_name(type, name)

    case AccessChecker.plan_has_access?(query_or_argument, requested_product, plan_name) do
      false ->
        no_access_map(type_str, name_str)

      true ->
        case AccessChecker.restricted?(query_or_argument) do
          false ->
            not_restricted_access_map(type_str, name_str)

          true ->
            maybe_restricted_access_map(
              type_str,
              name_str,
              plan_name,
              requested_product,
              subscription_product,
              query_or_argument
            )
        end
    end
    |> post_process()
  end

  @doc ~s"""
  Return a list in which every element describes either a metric or a query.
  The elements are maps describing the time restrictions of the given metric/query.
  """
  @spec get_all(String.t(), String.t(), :query | :metric | :signal | nil) :: list(restriction)
  def get_all(plan_name, product_code, filter \\ nil) do
    metrics = Sanbase.Metric.available_metrics() |> Enum.map(&{:metric, &1})
    signals = Sanbase.Signal.available_signals() |> Enum.map(&{:signal, &1})
    queries = Sanbase.Project.AvailableQueries.all_atom_names() |> Enum.map(&{:query, &1})

    # elements are {:metric, <string>} or {:query, <atom>} or {:signal, <string>}
    result =
      (queries ++ metrics ++ signals)
      |> Enum.map(fn query_or_argument ->
        get(query_or_argument, product_code, product_code, plan_name)
      end)

    (get_extra_queries(plan_name, product_code) ++ result)
    |> Enum.uniq_by(& &1.name)
    |> Enum.sort_by(& &1.name)
    |> maybe_filter_by_type(filter)
  end

  # Private functions

  defp post_process(map) do
    map
    # Replace misssing `is_deprecated` with `false`. Replace `nil` with `false`.
    |> Map.update(:is_deprecated, false, fn value -> if is_nil(value), do: false, else: value end)
  end

  defp maybe_filter_by_type(list, nil), do: list

  defp maybe_filter_by_type(list, filter) do
    filter = to_string(filter)
    Enum.filter(list, &(&1.type == filter))
  end

  defp no_access_map(type_str, name_str) do
    additional_data = additional_data(type_str, name_str)

    %{
      type: type_str,
      name: name_str,
      human_readable_name: name_str,
      is_accessible: false,
      is_restricted: true,
      restricted_from: nil,
      restricted_to: nil
    }
    |> Map.merge(additional_data)
  end

  defp not_restricted_access_map(type_str, name_str) do
    additional_data = additional_data(type_str, name_str)

    %{
      type: type_str,
      name: name_str,
      is_accessible: true,
      is_restricted: false
    }
    |> Map.merge(additional_data)
  end

  defp maybe_restricted_access_map(
         type_str,
         name_str,
         plan_name,
         requested_product,
         subscription_product,
         query_or_metric
       ) do
    now = Timex.now()

    restricted_from =
      case AccessChecker.historical_data_in_days(
             query_or_metric,
             requested_product,
             subscription_product,
             plan_name
           ) do
        nil -> nil
        days -> Timex.shift(now, days: -days)
      end

    restricted_to =
      case AccessChecker.realtime_data_cut_off_in_days(
             query_or_metric,
             requested_product,
             subscription_product,
             plan_name
           ) do
        nil -> nil
        0 -> nil
        days -> Timex.shift(now, days: -days)
      end

    additional_data = additional_data(type_str, name_str)

    %{
      type: type_str,
      name: name_str,
      is_accessible: true,
      is_restricted: not is_nil(restricted_from) or not is_nil(restricted_to),
      restricted_from: restricted_from,
      restricted_to: restricted_to,
      # The metric additional data will override the docs field
      docs: []
    }
    |> Map.merge(additional_data)
  end

  defp construct_name(:metric, name), do: name |> to_string()
  defp construct_name(:signal, name), do: name |> to_string()
  defp construct_name(:query, name), do: name |> Inflex.camelize(:lower)

  defp additional_data("metric", metric) do
    case Sanbase.Metric.metadata(metric) do
      {:ok, metadata} ->
        {:ok, human_readable_name} = Sanbase.Metric.human_readable_name(metric)

        %{
          human_readable_name: human_readable_name,
          min_interval: metadata.min_interval,
          internal_name: metadata.internal_metric,
          is_deprecated: metadata.is_deprecated,
          hard_deprecate_after: metadata.hard_deprecate_after,
          docs: metadata.docs,
          available_selectors: metadata.available_selectors,
          required_selectors: metadata.required_selectors
        }

      {:error, error} ->
        raise(error)
    end
  end

  defp additional_data("signal", signal) do
    case Sanbase.Signal.metadata(signal) do
      {:ok, metadata} ->
        {:ok, human_readable_name} = Sanbase.Signal.human_readable_name(signal)

        %{
          human_readable_name: human_readable_name,
          min_interval: metadata.min_interval,
          internal_name: metadata.internal_signal,
          available_selectors: [],
          required_selectors: []
        }

      {:error, error} ->
        raise(error)
    end
  end

  defp additional_data("query", query)
       when query in [
              "dailyActiveDeposits",
              "historyTwitterData",
              "percentOfTokenSupplyOnExchanges"
            ],
       do: %{min_interval: "1d", internal_name: query}

  defp additional_data("query", query)
       when query in [
              "gasUsed",
              "devActivity",
              "githubActivity",
              "historicalBalance",
              "historyPrice",
              "socialDominance",
              "githubActivity",
              "minersBalance",
              "ohlc",
              "getProjectTrendingHistory",
              "ethSpentOverTime"
            ],
       do: %{min_interval: "5m", internal_name: query}

  defp additional_data("query", query),
    do: %{
      min_interval: nil,
      internal_name: query,
      available_selectors: [],
      required_selectors: []
    }

  defp get_extra_queries(_plan_name, _product_code) do
    [not_restricted_access_map("query", "ethSpentOverTime")]
    |> Enum.map(&post_process/1)
  end
end
