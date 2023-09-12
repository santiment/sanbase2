defmodule Sanbase.ModeratorQueries do
  @moduledoc ~s"""
  Santiment Queries Moderator functions
  """

  @type user_id :: non_neg_integer()

  @doc ~s"""
  Reset the monthly credits spent by a user.
  The credits spent are reset by setting the credits_cost field to 0, the rest of
  the fields are left untouched.
  """
  @spec reset_user_monthly_credits(user_id) :: :ok
  def reset_user_monthly_credits(user_id) do
    query =
      Sanbase.Queries.QueryExecution.get_user_monthly_executions(user_id, preload?: false)
      # Exclude order_by clause so update_all/2 can be executed
      |> Ecto.Query.exclude(:order_by)
      # To avoid match errors on the second `nil` element in the restult tuple
      |> Ecto.Query.exclude(:select)

    {_, nil} = Sanbase.Repo.update_all(query, set: [credits_cost: 0])

    :ok
  end
end
