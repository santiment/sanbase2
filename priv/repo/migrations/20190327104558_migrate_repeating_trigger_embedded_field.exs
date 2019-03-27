defmodule Sanbase.Repo.Migrations.MigrateRepeatingTriggerEmbeddedField do
  use Ecto.Migration

  def up do
    Application.ensure_all_started(:timex)

    execute("""
      UPDATE user_triggers
      SET trigger = trigger - 'repeating' || jsonb_build_object('is_repeating', trigger->'repeating')
      WHERE trigger ? 'repeating'
    """)
  end

  def down do
    Application.ensure_all_started(:timex)

    execute("""
      UPDATE user_triggers
      SET trigger = trigger - 'is_repeating' || jsonb_build_object('repeating', trigger->'is_repeating')
      WHERE trigger ? 'is_repeating'
    """)
  end
end
