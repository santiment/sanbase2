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
  def from_to_interval(%{} = args, child_complexity, %Absinthe.Complexity{
        context: %{auth: %{current_user: user}}
      }) do
    with {:ok, san_balance} when not is_nil(san_balance) <- Sanbase.Auth.User.san_balance(user) do
      san_balance = Decimal.to_float(san_balance)

      if san_balance >= 1000 do
        0
      else
        calculate_complexity(args, child_complexity)
      end
    else
      _ -> calculate_complexity(args, child_complexity)
    end
  end

  @doc ~S"""
  Returns the complexity of the query. It is the number of intervals in the period
  'from-to' multiplied by the child complexity. The child complexity is the number
  of fields that will be returned for a single price point. The calculation is done
  based only on the supplied arguments and avoids accessing the DB if the query
  is rejected.
  """
  def from_to_interval(%{} = args, child_complexity, _) do
    calculate_complexity(args, child_complexity)
  end

  # Private functions

  defp calculate_complexity(%{from: from, to: to, interval: interval}, child_complexity) do
    from_unix = DateTime.to_unix(from, :second)
    to_unix = DateTime.to_unix(to, :second)
    years_difference_weighted = Timex.diff(from, to, :years) |> abs |> Kernel.*(2) |> max(1)
    interval = if interval == "", do: "1d", else: interval

    interval_seconds = Sanbase.DateTimeUtils.str_to_sec(interval)

    (child_complexity * ((to_unix - from_unix) / interval_seconds) * years_difference_weighted)
    |> Float.floor()
    |> Kernel.trunc()
  end
end
