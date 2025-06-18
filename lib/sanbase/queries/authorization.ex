defmodule Sanbase.Queries.Authorization do
  alias Sanbase.Accounts.User

  @doc ~s"""
  Returns the dynamic repo whose credentials have the least restrictions.
  This is used to execute queries when basic auth is used
  """
  @spec max_access_dynamic_repo() :: module()
  def max_access_dynamic_repo() do
    Sanbase.ClickhouseRepo.BusinessMaxUser
  end

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

  @doc ~s"""
  Convert the user's plan to a dynamic Clickhouse repo.
  """
  @spec user_plan_to_dynamic_repo(String.t(), String.t()) :: module()
  def user_plan_to_dynamic_repo(product_code, plan_name) do
    case {product_code, plan_name} do
      {_, "FREE"} ->
        Sanbase.ClickhouseRepo.FreeUser

      {"SANBASE", "PRO"} ->
        Sanbase.ClickhouseRepo.SanbaseProUser

      {"SANBASE", "PRO_PLUS"} ->
        Sanbase.ClickhouseRepo.SanbaseMaxUser

      {"SANBASE", "MAX"} ->
        Sanbase.ClickhouseRepo.SanbaseMaxUser

      {"SANAPI", "BASIC"} ->
        Sanbase.ClickhouseRepo.SanbaseMaxUser

      {"SANAPI", "PRO"} ->
        Sanbase.ClickhouseRepo.BusinessProUser

      {"SANAPI", "BUSINESS_PRO"} ->
        Sanbase.ClickhouseRepo.BusinessProUser

      {"SANAPI", "BUSINESS_MAX"} ->
        Sanbase.ClickhouseRepo.BusinessMaxUser

      {"SANAPI", "CUSTOM"} ->
        Sanbase.ClickhouseRepo.ReadOnly

      {"SANAPI", "CUSTOM_" <> _ = custom_plan} ->
        user_plan_to_dynamic_repo("SANAPI", fetch_base_plan_for_custom(custom_plan))
    end
  end

  def query_executions_limit(product_code, plan_name) do
    case {product_code, plan_name} do
      {_, "FREE"} ->
        %{minute: 20, hour: 200, day: 500}

      {"SANBASE", "PRO"} ->
        %{minute: 50, hour: 1000, day: 5000}

      {"SANBASE", "PRO_PLUS"} ->
        %{minute: 50, hour: 2000, day: 10_000}

      {"SANBASE", "MAX"} ->
        %{minute: 50, hour: 2000, day: 10_000}

      {"SANAPI", "BASIC"} ->
        %{minute: 50, hour: 2000, day: 10_000}

      {"SANAPI", "PRO"} ->
        %{minute: 100, hour: 3000, day: 15_000}

      {"SANAPI", "BUSINESS_PRO"} ->
        %{minute: 100, hour: 3000, day: 15_000}

      {"SANAPI", "BUSINESS_MAX"} ->
        %{minute: 100, hour: 3000, day: 15_000}

      {"SANAPI", "CUSTOM"} ->
        %{minute: 200, hour: 3000, day: 20_000}

      {"SANAPI", "CUSTOM_" <> _ = custom_plan} ->
        query_executions_limit("SANAPI", fetch_base_plan_for_custom(custom_plan))
    end
  end

  def credits_limit(product_code, plan_name) do
    case {product_code, plan_name} do
      {_, "FREE"} ->
        500

      {"SANBASE", "PRO"} ->
        10_000

      {"SANBASE", "PRO_PLUS"} ->
        20_000

      {"SANBASE", "MAX"} ->
        20_000

      {"SANAPI", "BASIC"} ->
        20_000

      {"SANAPI", "PRO"} ->
        50_000

      {"SANAPI", "BUSINESS_PRO"} ->
        50_000

      {"SANAPI", "BUSINESS_MAX"} ->
        500_000

      {"SANAPI", "CUSTOM"} ->
        500_000

      {"SANAPI", "CUSTOM_" <> _ = custom_plan} ->
        credits_limit("SANAPI", fetch_base_plan_for_custom(custom_plan))
    end
  end

  # Private functions

  def fetch_base_plan_for_custom(custom_plan) do
    Sanbase.Billing.Plan.CustomPlan.Loader.get_data(custom_plan, "SANAPI")
    |> case do
      {:error, _} ->
        "FREE"

      custom_plan_access ->
        get_in(custom_plan_access, [
          Access.key!(:restrictions),
          Access.key!(:restricted_access_as_plan)
        ]) || "FREE"
    end
  end

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
end
