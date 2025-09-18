defmodule Sanbase.Repo.Migrations.FaqEntriesQuestionUniqueIndex do
  use Ecto.Migration

  def change do
    create(unique_index(:faq_entries, [:question], name: :faq_entries_question_index))
  end
end
