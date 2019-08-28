defmodule Sanbase.Repo.Migrations.RemoveLogo32Url do
  use Ecto.Migration

  def change do
    alter table("project") do
      remove(:logo32_url)
    end
  end
end
