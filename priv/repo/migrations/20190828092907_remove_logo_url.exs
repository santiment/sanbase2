defmodule Sanbase.Repo.Migrations.RemoveLogoUrl do
  use Ecto.Migration

  def change do
    alter table("project") do
      remove(:logo_url)
    end
  end
end
