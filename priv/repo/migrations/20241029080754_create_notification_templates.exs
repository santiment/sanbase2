defmodule Sanbase.Repo.Migrations.CreateNotificationTemplates do
  use Ecto.Migration

  def change do
    create table(:notification_templates) do
      add(:channel, :string)
      add(:action_type, :string)
      add(:step, :string)
      add(:template, :text)

      timestamps()
    end

    create(index(:notification_templates, [:action_type, :step]))
    create(index(:notification_templates, [:channel]))

    create(unique_index(:notification_templates, [:action_type, :step, :channel]))
  end
end
