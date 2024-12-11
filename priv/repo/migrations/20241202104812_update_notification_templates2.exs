defmodule Sanbase.Repo.Migrations.UpdateNotificationTemplates2 do
  use Ecto.Migration

  def change do
    rename(table(:notification_templates), :action_type, to: :action)

    alter table(:notification_templates) do
      add(:mime_type, :string, default: "text/plain")
      add(:required_params, {:array, :string}, default: [])
    end
  end
end
