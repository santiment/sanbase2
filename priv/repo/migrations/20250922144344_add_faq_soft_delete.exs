defmodule Sanbase.Repo.Migrations.AddFaqSoftDelete do
  use Ecto.Migration

  def change do
    alter(table(:faq_entries)) do
      add(:is_deleted, :boolean, default: false, null: false)
    end
  end
end
