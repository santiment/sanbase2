defmodule Sanbase.Repo.Migrations.CreateWebinarRegistration do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:webinar_registrations) do
      add(:user_id, references(:users, on_delete: :delete_all))
      add(:webinar_id, references(:webinars, on_delete: :delete_all))

      timestamps()
    end

    create(index(:webinar_registrations, [:user_id]))
    create(index(:webinar_registrations, [:webinar_id]))
    create(unique_index(:webinar_registrations, [:user_id, :webinar_id]))
  end
end
