defmodule Sanbase.Repo.Migrations.RenameLogoFields do
  @moduledoc false
  use Ecto.Migration

  def up do
    rename(table("project"), :logo_32_url, to: :logo32_url)
    rename(table("project"), :logo_64_url, to: :logo64_url)
  end

  def down do
    rename(table("project"), :logo32_url, to: :logo_32_url)
    rename(table("project"), :logo64_url, to: :logo_64_url)
  end
end
