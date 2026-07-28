defmodule Sanbase.Repo.Migrations.MigrateObanV14 do
  use Ecto.Migration

  alias Sanbase.Utils.Config

  # Oban 2.23 ships schema version 14. The database is at version 11, so
  # versions 12, 13 and 14 are applied here:
  #
  #   v12 - replaces the `priority_range` check constraint with an unvalidated
  #         `non_negative_priority` one and drops the unused `oban_notify`
  #         insert trigger and function.
  #   v13 - adds indexes on (state, cancelled_at) and (state, discarded_at).
  #   v14 - adds the `suspended` value to the `oban_job_state` enum. Oban 2.23
  #         includes `suspended` in the `:incomplete` unique state group used by
  #         the cryptocompare pause/resume workers, so the enum value has to
  #         exist before those jobs are inserted.
  def up() do
    Oban.Migrations.up(prefix: get_prefix())
  end

  def down() do
    # 11 is the previous version
    Oban.Migrations.down(version: 11, prefix: get_prefix())
  end

  defp get_prefix() do
    case Config.module_get(Sanbase, :deployment_env) do
      env when env in ["stage", "prod"] -> "sanbase2"
      _ -> "public"
    end
  end
end
