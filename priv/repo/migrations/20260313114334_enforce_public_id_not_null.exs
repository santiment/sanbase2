defmodule Sanbase.Repo.Migrations.EnforcePublicIdNotNull do
  use Ecto.Migration

  def change do
    alter table(:users) do
      modify(:public_id, :uuid, null: false, default: fragment("gen_random_uuid()"))
    end
  end
end
