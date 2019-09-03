defmodule Sanbase.Repo.Migrations.RenameLogo64UrlToLogoUrl do
  use Ecto.Migration

  def change do
    rename(table("project"), :logo64_url, to: :logo_url)
  end
end
