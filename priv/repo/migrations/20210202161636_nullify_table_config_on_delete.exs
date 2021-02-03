defmodule Sanbase.Repo.Migrations.NullifyTableConfigOnDelete do
  use Ecto.Migration

  def change do
    alter table(:user_lists) do
      modify(:table_configuration_id, references(:device_type, on_delete: :nilify_all))
    end
  end
end
