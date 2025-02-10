defmodule Sanbase.Metric.Registry.Permissions do
  @moduledoc false
  def can?(:create, _) do
    # Will depend on the user roles as well
    deployment_env() == "stage" or (deployment_env() == "dev" and not aws_db_url?())
  end

  def can?(:edit, _) do
    # Will depend on the user roles as well
    deployment_env() == "stage" or (deployment_env() == "dev" and not aws_db_url?())
  end

  def can?(:start_sync, _) do
    # Will depend on the user roles as well
    deployment_env() == "stage" or (deployment_env() == "dev" and not aws_db_url?())
  end

  def can?(:apply_change_suggestions, _) do
    # Will depend on the user roles
    true
  end

  defp deployment_env do
    Sanbase.Utils.Config.module_get(Sanbase, :deployment_env)
  end

  defp aws_db_url? do
    db_url = System.get_env("DATABASE_URL")
    is_binary(db_url) and db_url =~ "aws"
  end
end
