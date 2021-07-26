defmodule Sanbase.Repo.Migrations.AddUserAvatar do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:avatar_url, :string)
    end
  end
end
