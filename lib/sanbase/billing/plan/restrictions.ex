defmodule Sanbase.Billing.Plan.Restrictions do
  @moduledoc ~s"""
  Work with the access restrictions for all queries and metrics.
  A time restrictions is defined by the query/metric, subscription and plan.
  """

  alias Sanbase.Billing.{Subscription, Plan.AccessChecker}

  @type restriction :: %{
          type: String.t(),
          name: String.t(),
          is_restricted: boolean(),
          restricted_from: DateTime.t(),
          restricted_to: DateTime.t()
        }

  @spec get(query_or_metric, %Subscription{}, non_neg_integer()) :: restriction()
        when query_or_metric: {:metric, String.t()} | {:query, atom()}
  def get({type, name}, subscription, product_id) when type in [:metric, :query] do
    now = Timex.now()

    type_str = type |> to_string()
    name_str = construct_name(type, name)

    case AccessChecker.is_restricted?({type, name}) do
      false ->
        %{
          type: type_str,
          name: name_str,
          is_restricted: false
        }

      true ->
        restricted_from =
          case Subscription.historical_data_in_days(subscription, {type, name}, product_id) do
            nil -> nil
            days -> Timex.shift(now, days: -days)
          end

        restricted_to =
          case Subscription.realtime_data_cut_off_in_days(subscription, {type, name}, product_id) do
            nil -> nil
            days -> Timex.shift(now, days: -days)
          end

        %{
          type: type_str,
          name: name_str,
          is_restricted: not (is_nil(restricted_from) or is_nil(restricted_to)),
          restricted_from: restricted_from,
          restricted_to: restricted_to
        }
    end
  end

  @doc ~s"""
  Return a list in which every element describes either a metric or a query.
  The elements are maps describing the time restrictions of the given metric/query.
  """
  @spec get_all(%Subscription{}, non_neg_integer()) :: list(restriction)
  def get_all(subscription, product_id) do
    metrics = Sanbase.Metric.available_metrics() |> Enum.map(&{:metric, &1})

    queries =
      Sanbase.Model.Project.AvailableQueries.all_atom_names()
      |> Enum.map(&{:query, &1})

    # elements are {:metric, <string>} or {:query, <atom>}
    (queries ++ metrics)
    |> Enum.map(fn metric_or_query -> get(metric_or_query, subscription, product_id) end)
  end

  defp construct_name(:metric, name), do: name |> to_string()
  defp construct_name(:query, name), do: name |> Inflex.camelize(:lower)
end
