defmodule Sanbase.Repo.Migrations.AddPostDiscourseLink do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add(:discourse_topic_url, :string)
    end
  end
end
