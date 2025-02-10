defmodule Sanbase.Repo.Migrations.AddLogoFields do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:project) do
      add(:logo_32_url, :string)
      add(:logo_64_url, :string)
    end
  end
end
