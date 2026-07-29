defmodule Sanbase.Repo.Migrations.MigrateObanV14 do
  @moduledoc """
  Migrates the Oban schema from version 11 to version 14.

  Oban 2.23 ships schema version 14 and refuses to boot against an older
  database (`Oban.Migration.verify_migrated!/1`), so versions 12, 13 and 14
  are applied here:

    * v12 - replaces the `priority_range` check constraint with an
      unvalidated `non_negative_priority` one and drops the unused
      `oban_notify` insert trigger and function.
    * v13 - adds indexes on `(state, cancelled_at)` and
      `(state, discarded_at)`.
    * v14 - adds the `suspended` value to the `oban_job_state` enum. Oban
      2.23 includes `suspended` in the `:incomplete` unique state group used
      by the cryptocompare pause/resume workers, so the enum value has to
      exist before those jobs are inserted.

  Both directions pin an explicit version so a future Oban bump cannot
  silently change what this migration does.

  `Oban.Migrations.down/1` is inclusive of the version it is given and
  records `version - 1`, so `down/0` passes 12 to undo v14, v13 and v12 and
  land back on 11 — exactly what `up/0` applied.
  """

  use Ecto.Migration

  alias Sanbase.Utils.Config

  @doc """
  Applies Oban schema versions 12 through 14.

  ## Examples

      iex> Sanbase.Repo.Migrations.MigrateObanV14.up()
      :ok
  """
  @spec up() :: :ok
  def up() do
    Oban.Migrations.up(version: 14, prefix: get_prefix())
  end

  @doc """
  Reverts Oban schema versions 14, 13 and 12, leaving the database on 11.

  ## Examples

      iex> Sanbase.Repo.Migrations.MigrateObanV14.down()
      :ok
  """
  @spec down() :: :ok | nil
  def down() do
    Oban.Migrations.down(version: 12, prefix: get_prefix())
  end

  defp get_prefix() do
    case Config.module_get(Sanbase, :deployment_env) do
      env when env in ["stage", "prod"] ->
        "sanbase2"

      env when env in ["dev", "test"] ->
        "public"

      env ->
        raise ArgumentError,
              "Refusing to migrate Oban: unsupported deployment_env #{inspect(env)}. " <>
                "Set DEPLOYMENT_ENVIRONMENT to one of dev, test, stage or prod."
    end
  end
end
