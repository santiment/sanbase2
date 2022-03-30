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

  def add_dashboard_panel(_root, args, %{context: %{auth: %{current_user: user}}}) do
    with true <- can_edit_dashboard?(args.dashboard_id, user.id) do
      Dashboard.add_panel(args.dashboard_id, args.panel)
    end
  end

  def remove_dashboard_panel(_root, args, %{context: %{auth: %{current_user: user}}}) do
    with true <- can_edit_dashboard?(args.dashboard_id, user.id) do
      Dashboard.remove_panel(args.dashboard_id, args.panel_id)
    end
  end

  def update_dashboard_panel(_root, args, %{context: %{auth: %{current_user: user}}}) do
    with true <- can_edit_dashboard?(args.dashboard_id, user.id) do
      Dashboard.update_panel(args.dashboard_id, args.panel_id, args.panel)
    end
  end

  def compute_dashboard_panel(_root, args, %{context: %{auth: %{current_user: user}}}) do
    with true <- can_view_dashboard?(args.dashboard_id, user.id) do
      Dashboard.compute_panel(args.dashboard_id, args.panel_id)
    end
  end

  def get_dashboard_schema(_root, args, %{context: %{auth: %{current_user: user}}}) do
    with true <- can_view_dashboard?(args.dashboard_id, user.id) do
      Dashboard.load_schema(args.dashboard_id)
    end
  end

  def get_dashboard_cache(_root, args, %{context: %{auth: %{current_user: user}}}) do
    with true <- can_view_dashboard?(args.dashboard_id, user.id) do
      Dashboard.load_cache(args.dashboard_id)
    end
  end

  defp can_view_dashboard?(dashboard_id, user_id) do
    # Users can see their own dashboard and other people's public dashboards
    IO.inspect({user_id, Dashboard.get_access_data(dashboard_id)})

    case Dashboard.get_access_data(dashboard_id) do
      {:ok, %{user_id: ^user_id}} -> true
      {:ok, %{is_public: true}} -> true
      _ -> {:error, "Dashboard is private or does not exist"}
    end
  end

  defp can_edit_dashboard?(dashboard_id, user_id) do
    case Dashboard.get_access_data(dashboard_id) do
      {:ok, %{user_id: ^user_id}} -> true
      _ -> {:error, "Dashboard is private or does not exist"}
    end
  end
end
