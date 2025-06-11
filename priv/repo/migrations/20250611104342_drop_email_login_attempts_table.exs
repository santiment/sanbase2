defmodule Sanbase.Repo.Migrations.DropEmailLoginAttemptsTable do
  use Ecto.Migration

  def up do
    drop(table(:email_login_attempts))
  end

  def down do
    :ok
  end
end
