defmodule Sanbase.Metric.Registry.Permissions do
  @view "Metric Registry Viewer"
  @edit "Metric Registry Change Suggester"
  @approve "Metric Registry Change Approver"
  @deployer "Metric Registry Deployer"
  @owner "Metric Registry Owner"

  def can?(action, opts) do
    if @owner in Keyword.get(opts, :roles, []) do
      true
    else
      check_permission(action, opts)
    end
  end

  # Private functions

  def check_permission(:create, opts) do
    stage_or_dev?() and any_role?([@edit], opts)
  end

  def check_permission(:edit, opts) do
    stage_or_dev?() and any_role?([@edit], opts)
  end

  def check_permission(:start_sync, opts) do
    stage_or_dev?() and any_role?([@deployer], opts)
  end

  def check_permission(:apply_change_suggestions, opts) do
    stage_or_dev?() and any_role?([@approve], opts)
  end

  def check_permission(:access_verified_status, _) do
    # Will depend on the user roles as well
    stage_or_dev?()
  end

  def check_permission(:access_sync_status, _) do
    # Will depend on the user roles as well
    stage_or_dev?()
  end

  def check_permission(:see_history, _) do
    true
  end

  def check_permission(:see_sync_runs, _) do
    true
  end

  # Helpers

  defp stage_or_dev?() do
    deployment_env() == "stage" or (deployment_env() == "dev" and not aws_db_url?())
  end

  defp any_role?(any_of_these_roles, opts) do
    user_roles = Keyword.get(opts, :roles, [])
    Enum.any?(any_of_these_roles, &(&1 in user_roles))
  end

  defp deployment_env() do
    Sanbase.Utils.Config.module_get(Sanbase, :deployment_env)
  end

  defp aws_db_url?() do
    db_url = System.get_env("DATABASE_URL")
    is_binary(db_url) and db_url =~ "aws"
  end
end
