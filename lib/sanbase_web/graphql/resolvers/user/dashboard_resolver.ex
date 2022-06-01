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
    with true <- can_view_dashboard?(args.dashboard_id, user.id),
         true <- can_run_computation?(user.id) do
      Dashboard.compute_panel(args.dashboard_id, args.panel_id)
    end
  end

  def compute_and_store_dashboard_panel(_root, args, %{context: %{auth: %{current_user: user}}}) do
    # storing requires edit access, not just view access
    with true <- can_edit_dashboard?(args.dashboard_id, user.id),
         true <- can_run_computation?(user.id) do
      Dashboard.compute_and_store_panel(args.dashboard_id, args.panel_id)
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

    case Dashboard.get_is_public_and_owner(dashboard_id) do
      {:ok, %{user_id: ^user_id}} -> true
      {:ok, %{is_public: true}} -> true
      _ -> {:error, "Dashboard is private or does not exist"}
    end
  end

  defp can_edit_dashboard?(dashboard_id, user_id) do
    case Dashboard.get_is_public_and_owner(dashboard_id) do
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
