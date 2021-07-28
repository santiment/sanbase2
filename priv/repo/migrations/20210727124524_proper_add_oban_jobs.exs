defmodule Sanbase.Repo.Migrations.ProperAddObanJobs do
  use Ecto.Migration

  require Sanbase.Utils.Config, as: Config

  def up do
    Oban.Migrations.up(prefix: get_prefix())
  end

  def down do
    Oban.Migrations.down(version: 1, prefix: get_prefix())
  end

  defp get_prefix() do
    case Config.module_get(Sanbase, :deployment_env) do
      env when env in ["stage", "prod"] -> "sanbase2"
      _ -> "public"
    end
  end
end
