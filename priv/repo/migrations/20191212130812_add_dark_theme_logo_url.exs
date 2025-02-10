defmodule Sanbase.Repo.Migrations.AddDarkThemeLogoUrl do
  @moduledoc false
  use Ecto.Migration

  def up do
    alter table("project") do
      add(:dark_logo_url, :string)
    end
  end

  def down do
    alter table("project") do
      remove(:dark_logo_url)
    end
  end
end
