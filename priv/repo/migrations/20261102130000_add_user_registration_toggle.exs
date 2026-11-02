defmodule Sanbase.Repo.Migrations.AddUserRegistrationToggle do
  use Ecto.Migration

  # Insert the toggle rows, enabled, so the admin panel always has rows to edit.
  # The admin page cannot create toggles.
  def up() do
    execute("""
    INSERT INTO feature_toggles (name, enabled, inserted_at, updated_at)
    VALUES
      ('user_registration', true, now(), now()),
      ('eth_registration', true, now(), now())
    ON CONFLICT (name) DO NOTHING
    """)
  end

  # Keep the rows on rollback, so the admin's settings survive a rollback and
  # re-run (`up/0` does not overwrite an existing row).
  def down(), do: :ok
end
