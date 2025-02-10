defmodule Sanbase.Repo.Migrations.RenameLogoColumns do
  @moduledoc false
  use Ecto.Migration

  def up do
    # Drop all possible logo columns. The frist 2 are present on stage
    # The second 2 will be present on prod because the migration that will execute
    # is the new one. They must be dropped so the `add` succeeds
    execute("ALTER TABLE project DROP COLUMN IF EXISTS logo_url_32;")
    execute("ALTER TABLE project DROP COLUMN IF EXISTS logo_url_64;")
    execute("ALTER TABLE project DROP COLUMN IF EXISTS logo_32_url;")
    execute("ALTER TABLE project DROP COLUMN IF EXISTS logo_64_url;")

    alter table("project") do
      add(:logo_32_url, :string)
      add(:logo_64_url, :string)
    end
  end

  def down do
    alter table("project") do
      remove(:logo_32_url)
      remove(:logo_64_url)
    end
  end
end
