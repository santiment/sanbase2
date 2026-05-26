defmodule Sanbase.Repo.Migrations.AddIndexVersionToAcademyArticles do
  use Ecto.Migration

  def change do
    alter table(:academy_articles) do
      add(:index_version, :integer, null: false, default: 0)
    end
  end
end
