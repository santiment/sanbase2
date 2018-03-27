defmodule Sanbase.Repo.Migrations.NotificationsAddDataField do
  use Ecto.Migration

  def change do
    alter table(:notification) do
      add(:data, :text)
    end
  end
end
