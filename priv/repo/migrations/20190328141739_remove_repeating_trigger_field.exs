defmodule Sanbase.Repo.Migrations.RemoveRepeatingTriggerField do
  use Ecto.Migration

  def up do
    execute("""
      UPDATE user_triggers 
      SET trigger = trigger #- '{settings,repeating}' 
      WHERE trigger->'settings' ? 'repeating'
    """)
  end
end
