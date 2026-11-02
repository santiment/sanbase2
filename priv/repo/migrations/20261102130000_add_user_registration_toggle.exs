defmodule Sanbase.Repo.Migrations.AddUserRegistrationToggle do
  use Ecto.Migration

  # Insert the toggle row, enabled, so the admin panel always has a row to edit.
  # The admin page cannot create toggles.
  def up() do
    execute("""
    INSERT INTO feature_toggles (name, enabled, inserted_at, updated_at)
    VALUES ('user_registration', true, now(), now())
    ON CONFLICT (name) DO NOTHING
    """)
  end

  def down() do
    execute("DELETE FROM feature_toggles WHERE name = 'user_registration'")
  end
end
