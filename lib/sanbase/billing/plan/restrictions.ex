defmodule Sanbase.Billing.Plan.Restrictions do
  @moduledoc ~s"""
  Work with the access restrictions for all queries and metrics.
  A time restrictions is defined by the query/metric, subscription and plan.
  """

  alias Sanbase.Billing.{Product, Subscription, Plan.AccessChecker}

  @type restriction :: %{
          type: String.t(),
          name: String.t(),
          is_restricted: boolean(),
          restricted_from: DateTime.t(),
          restricted_to: DateTime.t()
        }

  @doc ~s"""
  Return a list in which every element describes either a metric or a query.
  The elements are maps describing the time restrictions of the given metric/query.
  """
  @spec get(%Subscription{}, %Product{}) :: list(restriction)
  def get(subscription, product) do
    metrics = Sanbase.Metric.available_metrics() |> Enum.map(&{:metric, &1})
    queries = Sanbase.Model.Project.AvailableQueries.all() |> Enum.map(&{:query, &1})

    now = Timex.now()

    # elements are {:metric, <string>} or {:query, <atom>}
    (queries ++ metrics)
    |> Enum.map(fn {type, name} ->
      type_str = type |> to_string()
      name_str = name |> to_string()

      case AccessChecker.is_restricted?({type, name}) do
        false ->
          %{
            type: type_str,
            name: name_str,
            is_restricted: false
          }

        true ->
          restricted_from =
            case Subscription.historical_data_in_days(subscription, {type, name}, product) do
              nil -> nil
              days -> Timex.shift(now, days: -days)
            end

          restricted_to =
            case Subscription.realtime_data_cut_off_in_days(subscription, {type, name}, product) do
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
    end)
  end
end
