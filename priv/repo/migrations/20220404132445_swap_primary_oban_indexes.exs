defmodule Sanbase.Repo.Migrations.SwapPrimaryObanIndexes do
  @moduledoc false
  use Ecto.Migration

  require Sanbase.Utils.Config, as: Config

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create_if_not_exists(
      index(
        :oban_jobs,
        [:state, :queue, :priority, :scheduled_at, :id],
        concurrently: true,
        prefix: get_prefix()
      )
    )

    drop_if_exists(
      index(
        :oban_jobs,
        [:queue, :state, :priority, :scheduled_at, :id],
        prefix: get_prefix()
      )
    )
  end

  defp get_prefix do
    case Config.module_get(Sanbase, :deployment_env) do
      env when env in ["stage", "prod"] -> "sanbase2"
      _ -> "public"
    end
  end
end
