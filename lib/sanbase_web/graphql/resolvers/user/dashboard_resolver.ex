defmodule SanbaseWeb.Graphql.Resolvers.DashboardResolver do
  @moduledoc ~s"""
  Module with resolvers connected to the Apikey authentication. All the logic
  is delegated to the `Apikey` module
  """

  require Logger

  alias Sanbase.Dashboard

  def create_dashboard(_root, args, %{context: %{auth: %{current_user: user}}}) do
    Dashboard.create(args, user.id)
  end

  def update_dashboard(_root, args, %{context: %{auth: %{current_user: user}}}) do
    with true <- can_edit_dashboard?(args.id, user.id) do
      Dashboard.update(args.id, args)
    end
  end

  def delete_dashboard(_root, args, %{context: %{auth: %{current_user: user}}}) do
    with true <- can_edit_dashboard?(args.id, user.id) do
      Dashboard.delete(args.id)
    end
  end

  def create_dashboard_panel(_root, args, %{context: %{auth: %{current_user: user}}}) do
    with true <- can_edit_dashboard?(args.dashboard_id, user.id),
         {:ok, %{} = result} <- Dashboard.create_panel(args.dashboard_id, args.panel) do
      {:ok, result.panel |> Map.put(:dashboard_id, result.dashboard.id)}
    end
  end

  def remove_dashboard_panel(_root, args, %{context: %{auth: %{current_user: user}}}) do
    %{dashboard_id: dashboard_id, panel_id: panel_id} = args

    with true <- can_edit_dashboard?(dashboard_id, user.id),
         {:ok, %{} = result} <- Dashboard.remove_panel(dashboard_id, panel_id) do
      {:ok, result.panel |> Map.put(:dashboard_id, dashboard_id)}
    end
  end

  def update_dashboard_panel(_root, args, %{context: %{auth: %{current_user: user}}}) do
    %{dashboard_id: dashboard_id, panel_id: panel_id, panel: panel} = args

    with true <- can_edit_dashboard?(dashboard_id, user.id),
         {:ok, %{} = result} <- Dashboard.update_panel(dashboard_id, panel_id, panel) do
      {:ok, result.panel |> Map.put(:dashboard_id, dashboard_id)}
    end
  end

  def compute_dashboard_panel(_root, args, %{context: %{auth: %{current_user: user}}}) do
    %{dashboard_id: dashboard_id, panel_id: panel_id} = args

    with true <- can_view_dashboard?(dashboard_id, user.id),
         true <- can_run_computation?(user.id) do
      Dashboard.compute_panel(dashboard_id, panel_id)
    end
  end

  def compute_and_store_dashboard_panel(_root, args, %{context: %{auth: %{current_user: user}}}) do
    %{dashboard_id: dashboard_id, panel_id: panel_id} = args
    # storing requires edit access, not just view access
    with true <- can_edit_dashboard?(dashboard_id, user.id),
         true <- can_run_computation?(user.id) do
      Dashboard.compute_and_store_panel(dashboard_id, panel_id)
    end
  end

  def get_dashboard_schema(_root, args, %{context: %{auth: %{current_user: user}}}) do
    with true <- can_view_dashboard?(args.id, user.id) do
      Dashboard.load_schema(args.id)
    end
  end

  def get_dashboard_cache(_root, args, %{context: %{auth: %{current_user: user}}}) do
    with true <- can_view_dashboard?(args.id, user.id),
         {:ok, dashboard_cache} <- Dashboard.load_cache(args.id) do
      panels =
        Enum.map(dashboard_cache.panels, fn {panel_id, panel_cache} ->
          Map.put(panel_cache, :id, panel_id)
        end)

      {:ok, %{dashboard_cache | panels: panels}}
    end
  end

  def compute_raw_clickhouse_query(_root, args, %{context: %{auth: %{current_user: user}}}) do
    san_query_id = UUID.uuid4()

    with true <- can_run_computation?(user.id),
         true <- Sanbase.Dashboard.Query.valid_sql?(args),
         {:ok, query_result} <-
           Sanbase.Dashboard.Query.run(args.query, args.parameters, san_query_id) do
      Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
        Dashboard.QueryExecution.store_execution(user.id, query_result)
      end)

      {:ok, query_result}
    end
  end

  # Private functions

  defp can_view_dashboard?(id, user_id) do
    # Users can see their own dashboard and other people's public dashboards

    case Dashboard.get_is_public_and_owner(id) do
      {:ok, %{user_id: ^user_id}} -> true
      {:ok, %{is_public: true}} -> true
      _ -> {:error, "Dashboard is private or does not exist"}
    end
  end

  defp can_edit_dashboard?(id, user_id) do
    case Dashboard.get_is_public_and_owner(id) do
      {:ok, %{user_id: ^user_id}} ->
        true

      _ ->
        {:error,
         "Dashboard is private, does not exist or you don't have permission to execute this."}
    end
  end

  defp can_run_computation?(user_id) do
    case Dashboard.has_credits_left?(user_id) do
      true -> true
      false -> {:error, "The user with id #{user_id} has no credits left"}
    end
  end
end
