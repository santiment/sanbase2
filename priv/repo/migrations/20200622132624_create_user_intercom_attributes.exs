defmodule Sanbase.Repo.Migrations.CreateUserIntercomAttributes do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:user_intercom_attributes) do
      add(:properties, :map)
      add(:user_id, references(:users, on_delete: :nothing))

      timestamps()
    end

    create(index(:user_intercom_attributes, [:user_id]))
  end
end
