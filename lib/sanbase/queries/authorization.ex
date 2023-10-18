defmodule Sanbase.Queries.Authorization do
  alias Sanbase.Accounts.User

  @doc ~s"""
  Check if the user has credits left to run a computation.

  Each query has a cost in credits. The cost is computed based on the query
  profiling details - how much RAM memory it used, how much data it read from
  the disk, how big is the result, etc.
  """
  @spec user_can_execute_query(%User{}, String.t(), String.t()) :: :ok | {:error, String.t()}
  def user_can_execute_query(user, product_code, plan_name) do
    if user_has_limits?(user) do
      check_user_limits(user.id, product_code, plan_name)
    else
      :ok
    end
  end

  # Private functions

  defp check_user_limits(user_id, product_code, plan_name) do
    query_executions_limit = query_executions_limit(product_code, plan_name)
    monthly_credits_limit = credits_limit(product_code, plan_name)

    # Currently it can return only {:ok, map} tuple
    {:ok, summary} = Sanbase.Queries.user_executions_summary(user_id)

    case summary do
      %{monthly_credits_spent: credits_spent}
      when credits_spent >= monthly_credits_limit ->
        {:error, "The user with id #{user_id} has no credits left"}

      %{queries_executed_minute: count}
      when count >= query_executions_limit.minute ->
        {:error,
         "The user with id #{user_id} has executed more queries than allowed in a minute."}

      %{queries_executed_hour: count}
      when count >= query_executions_limit.hour ->
        {:error, "The user with id #{user_id} has executed more queries than allowed in a hour."}

      %{queries_executed_day: count}
      when count >= query_executions_limit.day ->
        {:error, "The user with id #{user_id} has executed more queries than allowed in a day."}

      _ ->
        :ok
    end
  end

  defp user_has_limits?(user) do
    if not is_nil(user.email) and String.ends_with?(user.email, "@santiment.net") do
      false
    else
      true
    end
  end

  defp query_executions_limit(product_code, plan_name) do
    case {product_code, plan_name} do
      {_, "FREE"} -> %{minute: 1, hour: 5, day: 10}
      {"SANBASE", "PRO"} -> %{minute: 10, hour: 100, day: 500}
      {"SANAPI", "BASIC"} -> %{minute: 20, hour: 200, day: 1000}
      {"SANAPI", "PRO"} -> %{minute: 50, hour: 600, day: 3000}
      {"SANAPI", "CUSTOM"} -> %{minute: 200, hour: 1000, day: 5000}
      {"SANAPI", "CUSTOM_" <> _} -> %{minute: 200, hour: 1000, day: 5000}
    end
  end

  defp credits_limit(product_code, plan_name) do
    case {product_code, plan_name} do
      {_, "FREE"} -> 5_000
      {"SANBASE", "PRO"} -> 1_000_000
      {"SANAPI", "BASIC"} -> 2_000_000
      {"SANAPI", "PRO"} -> 5_000_000
      {"SANAPI", "CUSTOM"} -> 20_000_000
      # This needs to be updated so its taken from the plan definition
      {"SANAPI", "CUSTOM_" <> _} -> 20_000_000
    end
  end
end
