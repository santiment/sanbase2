defmodule Sanbase.Repo.Migrations.RemoveLogo32Url do
  @moduledoc false
  use Ecto.Migration

  def up do
    alter table("project") do
      remove(:logo32_url)
    end
  end

  def down do
    alter table("project") do
      add(:logo32_url, :string)
    end
  end
end
