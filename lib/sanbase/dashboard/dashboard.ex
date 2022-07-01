defmodule Sanbase.Dashboard do
  @moduledoc ~s"""
  Dashboard is a collection of panels that execute user-written SQL
  against Clickhouse.

  This module dispatches between the internal representations of the
  dashboard, panels, credits cost computation.
  Dashboards have two representations: Schema and Cache

  Dashboard.Schema represents the configuration of the dashboard, stored
  in the databse. This includes the name, description, public status and panels'
  definitions - SQL, position, size, type, etc.

  Dashboard.Cache represents a computed dashboard, stored in the database. This is
  shown to users when they open a dashboard and holds the computed data in JSON
  format.

  The users of the dashboard should use both the Schema and Cache representations
  in order to build the whole view - the Schema is used to shown the static data
  (name, description, etc) and the Cahce is used to shown the dynamic data
  (the result of the SQL can change on every evaluation).
  """

  alias Sanbase.Dashboard

  @type user_id :: non_neg_integer()
  @type dashboard_id :: non_neg_integer()
  @type panel_id :: String.t()

  @max_credits_per_month 1_000_000

  defdelegate update(dashboard_id, args), to: Dashboard.Schema
  defdelegate get_is_public_and_owner(dashboard_id), to: Dashboard.Schema
  defdelegate create_panel(dashboard_id, panel_args), to: Dashboard.Schema
  defdelegate remove_panel(dashboard_id, panel_id), to: Dashboard.Schema
  defdelegate update_panel(dashboard_id, panel_id, args), to: Dashboard.Schema

  @doc ~s"""
  Create a new and empty dashboard

  The dashboards are created without any panels (SQL). Panels are then added
  by the add/update/remove functions
  """
  @spec create(Dashboard.Schema.schema_args(), user_id) ::
          {:ok, Dashboard.Schema.t()} | {:error, any}
  def create(args, user_id) do
    args = Map.put(args, :user_id, user_id)
    Dashboard.Schema.create(args)
  end

  def delete(dashboard_id) do
    Dashboard.Schema.delete(dashboard_id)
  end

  @doc ~s"""
  Get the dashboard schema

  The schema includes the static data that does not change after execution - name,
  description, panels' definition, public status, etc.
  """
  @spec load_schema(dashboard_id) :: {:ok, Dashboard.Schema.t()} | {:error, any()}
  def load_schema(dashboard_id), do: Dashboard.Schema.by_id(dashboard_id)

  @doc ~s"""
  Get the dashboard cached version

  The cache includes the list of latest results of the SQL queries that are executed.
  The keys in the list are the panel ids.
  """
  @spec load_cache(dashboard_id) :: {:ok, Dashboard.Cache.t()} | {:error, any()}
  def load_cache(dashboard_id), do: Dashboard.Cache.by_dashboard_id(dashboard_id)

  @doc ~s"""
  Check if a given user has credits left

  Credits are used to pay for query execution. For every month a user can
  execute queries for #{@max_credits_per_month} credits. This mechanism is
  used to prevent users from using the system to consume too much resources
  """
  @spec has_credits_left?(user_id) :: boolean()
  def has_credits_left?(user_id) do
    now = DateTime.utc_now()
    from = Timex.beginning_of_month(now)

    case Dashboard.QueryExecution.credits_spent(user_id, from, now) do
      {:ok, credits_spent} when credits_spent < @max_credits_per_month -> true
      _ -> false
    end
  end

  @doc ~s"""
  Trigger computation of a single panel of the dashboard
  """
  @spec compute_panel(dashboard_id(), panel_id(), user_id()) ::
          {:ok, Dashboard.Query.Result.t()} | {:error, String.t()}
  def compute_panel(dashboard_id, panel_id, querying_user_id) do
    with {:ok, dashboard} <- Dashboard.Schema.by_id(dashboard_id),
         {:ok, query_result} <- do_compute_panel(dashboard, panel_id) do
      Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
        Dashboard.QueryExecution.store_execution(querying_user_id, query_result)
      end)

      {:ok, Dashboard.Panel.Cache.from_query_result(query_result, panel_id, dashboard_id)}
    end
  end

  @doc ~s"""
  Trigger computation of a single panel of the dashboard.
  If the computation is successful, store the result in the cache.
  This function should be called by the dashboard owner as it will change
  this dashboard's cache.
  """
  @spec compute_and_store_panel(dashboard_id(), panel_id(), user_id()) ::
          {:ok, Dashboard.Cache.t()} | {:error, any()}
  def compute_and_store_panel(dashboard_id, panel_id, querying_user_id) do
    with {:ok, dashboard} <- Dashboard.Schema.by_id(dashboard_id),
         {:ok, query_result} <- do_compute_panel(dashboard, panel_id),
         {:ok, _} <- Dashboard.Cache.update_panel_cache(dashboard_id, panel_id, query_result) do
      Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
        Dashboard.QueryExecution.store_execution(querying_user_id, query_result)
      end)

      panel_cache = Dashboard.Panel.Cache.from_query_result(query_result, panel_id, dashboard_id)
      {:ok, panel_cache}
    end
  end

  @doc ~s"""
  Trigger computation of all panels of the dashboard.
  Update the cache for every successful computation.
  """
  @spec compute_and_store_dashboard(dashboard_id(), user_id()) ::
          {:ok, Dashboard.Cache.t()} | {:error, any()}
  def compute_and_store_dashboard(dashboard_id, querying_user_id) do
    {:ok, dashboard} = Dashboard.Schema.by_id(dashboard_id)

    Enum.reduce_while(dashboard.panels, nil, fn panel, _cache ->
      case compute_and_store_panel(dashboard_id, panel.id, querying_user_id) do
        {:ok, _cache} = ok_result -> {:cont, ok_result}
        {:error, _error} = error_result -> {:halt, error_result}
      end
    end)
  end

  # Compute the dashboard by computing every panel in it.
  defp do_compute_panel(%Dashboard.Schema{} = dashboard, panel_id) do
    case Enum.find(dashboard.panels, &(&1.id == panel_id)) do
      nil -> {:error, "Dashboard panel with id #{panel_id} does not exist"}
      panel -> Sanbase.Dashboard.Panel.compute(panel)
    end
  end
end
