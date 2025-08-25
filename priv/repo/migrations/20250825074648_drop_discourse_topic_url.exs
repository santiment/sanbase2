defmodule Sanbase.Repo.Migrations.DropDiscourseTopicUrl do
  use Ecto.Migration

  def up do
    alter table(:posts) do
      remove(:discourse_topic_url)
    end
  end

  def down do
    alter table(:posts) do
      add(:discourse_topic_url, :string)
    end
  end
end
