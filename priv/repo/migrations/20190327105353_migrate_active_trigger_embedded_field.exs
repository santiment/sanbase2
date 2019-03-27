defmodule Sanbase.Repo.Migrations.MigrateRepeatingTriggerEmbeddedFields do
  use Ecto.Migration

  def up do
    Application.ensure_all_started(:timex)

    execute("""
      UPDATE user_triggers
      SET trigger = trigger - 'active' || jsonb_build_object('is_active', trigger->'active')
      WHERE trigger ? 'active'
    """)
  end

  def down do
    Application.ensure_all_started(:timex)

    execute("""
      UPDATE user_triggers
      SET trigger = trigger - 'is_active' || jsonb_build_object('active', trigger->'is_active')
      WHERE trigger ? 'is_active'
    """)
  end
end
