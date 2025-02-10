defmodule Elixir.Sanbase.Repo.Migrations.MigrateObanV11 do
  @moduledoc false
  use Ecto.Migration

  require Sanbase.Utils.Config, as: Config

  def up do
    Oban.Migrations.up(prefix: get_prefix())
  end

  def down do
    # 10 is the previous version
    Oban.Migrations.down(version: 10, prefix: get_prefix())
  end

  defp get_prefix do
    case Config.module_get(Sanbase, :deployment_env) do
      env when env in ["stage", "prod"] -> "sanbase2"
      _ -> "public"
    end
  end
end
