defmodule Sanbase.Metric.Registry.Permissions do
  def can?(:create, _) do
    # Will depend on the user roles as well
    deployment_env() == "stage" or (deployment_env() == "dev" and not aws_db_url?())
  end

  def can?(:edit, _) do
    # Will depend on the user roles as well
    stage_or_dev?()
  end

  def can?(:start_sync, _) do
    # Will depend on the user roles as well
    stage_or_dev?()
  end

  def can?(:apply_change_suggestions, _) do
    # Will depend on the user roles
    stage_or_dev?()
  end

  def can?(:access_verified_status, _) do
    # Will depend on the user roles as well
    stage_or_dev?()
  end

  def can?(:access_sync_status, _) do
    # Will depend on the user roles as well
    stage_or_dev?()
  end

  def can?(:see_history, _) do
    true
  end

  def can?(:see_sync_runs, _) do
    true
  end

  defp stage_or_dev?() do
    deployment_env() == "stage" or (deployment_env() == "dev" and not aws_db_url?())
  end

  defp deployment_env() do
    Sanbase.Utils.Config.module_get(Sanbase, :deployment_env)
  end

  defp aws_db_url?() do
    db_url = System.get_env("DATABASE_URL")
    is_binary(db_url) and db_url =~ "aws"
  end
end
