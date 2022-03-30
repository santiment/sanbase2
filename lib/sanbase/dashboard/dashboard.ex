defmodule Sanbase.Dashboard do
  @moduledoc ~s"""
  Dashboard is a collection of panels that execute user-written SQL
  against Clickhouse.

  This module dispatches between the internal representations of the
  dashboard. Dashboards have two representations: Schema and Cache

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

  @type dashboard_id :: non_neg_integer()
  @type panel_id :: non_neg_integer()

  defdelegate get_access_data(dashboard_id), to: Dashboard.Schema
  defdelegate add_panel(dashboard_id, panel_args), to: Dashboard.Schema
  defdelegate remove_panel(dashboard_id, panel_id), to: Dashboard.Schema
  defdelegate update_panel(dashboard_id, panel_id, args), to: Dashboard.Schema

  @spec create(Dashboard.Schema.schema_args(), non_neg_integer) ::
          {:ok, Dashboard.Schema.t()} | {:error, any}
  def create(args, user_id) do
    args = Map.put(args, :user_id, user_id)
    Dashboard.Schema.new(args)
  end

  def update(dashboard_id, args) do
    Dashboard.Schema.update(dashboard_id, args)
  end

  @spec load_schema(dashboard_id) :: {:ok, Dashboard.Schema.t()} | {:error, any()}
  def load_schema(dashboard_id), do: Dashboard.Schema.by_id(dashboard_id)

  @spec load_cache(dashboard_id) :: {:ok, Dashboard.Cache.t()} | {:error, any()}
  def load_cache(dashboard_id), do: Dashboard.Cache.by_dashboard_id(dashboard_id)

  @doc ~s"""
  Trigger computation of a single panel of the dashboard
  """
  @spec compute_panel(dashboard_id(), panel_id()) :: {:ok, any()} | {:error, any()}
  def compute_panel(dashboard_id, panel_id) do
    with {:ok, dashboard} <- Dashboard.Schema.by_id(dashboard_id),
         {:ok, result} <- do_compute_panel(dashboard, panel_id) do
      # TODO: Transform result into a more usable type
      {:ok, result}
    end
  end

  @doc ~s"""
  Trigger computation of a single panel of the dashboard.
  If the computation is successful, store the result in the cache.
  This function should be called by the dashboard owner as it will change
  this dashboard's cache.
  """
  @spec compute_and_store_panel(dashboard_id(), panel_id()) ::
          {:ok, Dashboard.Cache.t()} | {:error, any()}
  def compute_and_store_panel(dashboard_id, panel_id) do
    with {:ok, dashboard} <- Dashboard.Schema.by_id(dashboard_id),
         {:ok, result} <- do_compute_panel(dashboard, panel_id) do
      Dashboard.Cache.update_panel_result(dashboard_id, panel_id, result)
    end
  end

  @doc ~s"""
  Trigger computation of all panels of the dashboard.
  Update the cache for every successful computation.
  """
  @spec compute_and_store_dashboard(dashboard_id()) ::
          {:ok, Dashboard.Cache.t()} | {:error, any()}
  def compute_and_store_dashboard(dashboard_id) do
    # TODO: Make async and implement retries in case of failure
    {:ok, dashboard} = Dashboard.Schema.by_id(dashboard_id)

    # The last result contains the fully built cache
    Enum.reduce_while(dashboard.panels, nil, fn panel, _cache ->
      case compute_and_store_panel(dashboard_id, panel.id) do
        {:ok, _cache} = ok_result -> {:cont, ok_result}
        {:error, _error} = error_result -> {:halt, error_result}
      end
    end)
  end

  # Compute the dashboard by computing every panel in it.
  defp do_compute_panel(%Dashboard.Schema{} = dashboard, panel_id) do
    case Enum.find(dashboard.panels, &(&1.id == panel_id)) do
      nil -> {:error, :panel_does_not_exist}
      panel -> {:ok, _result} = Sanbase.Dashboard.Panel.compute(panel)
    end
  end
end
