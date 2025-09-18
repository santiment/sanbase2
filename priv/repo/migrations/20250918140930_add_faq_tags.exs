defmodule Sanbase.Repo.Migrations.AddFaqTags do
  use Ecto.Migration

  def change do
    create table(:faq_entries_tags) do
      add(:faq_entry_id, references(:faq_entries, type: :binary_id))
      add(:tag_id, references(:tags, type: :bigint))
    end

    create(unique_index(:faq_entries_tags, [:faq_entry_id, :tag_id]))
  end
end
