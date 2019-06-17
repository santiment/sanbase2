defmodule SanbaseWeb.Graphql.Complexity do
  require Logger

  @doc ~S"""
  Internal services use basic authentication. Return complexity = 0 to allow them
  to access everything without limits.
  """
  def from_to_interval(_, _, %Absinthe.Complexity{context: %{auth: %{auth_method: :basic}}}) do
    0
  end

  @doc ~s"""
  Allow full access to a user if he or she has more than 1000 SAN tokens staked.
  If the logged in user has no SAN tokens or they cannot be fetched, fallback
  to the default complexity calculation
  """
  def from_to_interval(_args, _child_complexity, %Absinthe.Complexity{
        context: %{auth: %{san_balance: san_balance}}
      })
      when san_balance >= 1000 do
    0
  end

  @doc ~S"""
  Returns the complexity of the query. It is the number of intervals in the period
  'from-to' multiplied by the child complexity. The child complexity is the number
  of fields that will be returned for a single price point. The calculation is done
  based only on the supplied arguments and avoids accessing the DB if the query
  is rejected.
  """
  def from_to_interval(%{} = args, child_complexity, _complexity) do
    calculate_complexity(args, child_complexity)
  end

  # Private functions

  defp calculate_complexity(%{from: from, to: to} = args, child_complexity) do
    seconds_difference = Timex.diff(from, to, :seconds) |> abs
    years_difference_weighted = years_difference_weighted(from, to)
    interval_seconds = interval_seconds(args) |> max(60)

    (child_complexity * (seconds_difference / interval_seconds) * years_difference_weighted)
    |> Sanbase.Math.to_integer()
  end

  defp interval_seconds(args) do
    case Map.get(args, :interval, "") do
      "" -> "1d"
      interval -> interval
    end
    |> Sanbase.DateTimeUtils.str_to_sec()
  end

  defp years_difference_weighted(from, to) do
    Timex.diff(from, to, :years) |> abs |> max(1)
  end
end
