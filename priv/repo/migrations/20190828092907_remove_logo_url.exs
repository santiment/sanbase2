defmodule Sanbase.Repo.Migrations.RemoveLogoUrl do
  @moduledoc false
  use Ecto.Migration

  def up do
    alter table("project") do
      remove(:logo_url)
    end
  end

  def down do
    alter table("project") do
      add(:logo_url, :string)
    end
  end
end
