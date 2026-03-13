defmodule Sanbase.Repo.Migrations.AddPublicIdToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:public_id, :uuid, null: true, default: fragment("gen_random_uuid()"))
    end

    # Backfill all existing rows. With ~240k records this completes in ~1-2 seconds.
    # Uses gen_random_uuid() (v4) for the backfill — new users created through
    # Ecto will get UUIDv7 from application code.
    flush()

    execute(
      "UPDATE users SET public_id = gen_random_uuid() WHERE public_id IS NULL",
      "SELECT 1"
    )
  end
end
