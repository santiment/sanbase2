defmodule Sanbase.Repo.Migrations.FaqEntriesQuestionUniqueAmongLive do
  use Ecto.Migration

  # Rejected drafts are soft-deleted; their question can be drafted again.
  def up() do
    drop(index(:faq_entries, [:question], name: :faq_entries_question_index))

    create(
      unique_index(:faq_entries, [:question],
        name: :faq_entries_question_index,
        where: "is_deleted = false"
      )
    )
  end

  def down() do
    drop(index(:faq_entries, [:question], name: :faq_entries_question_index))
    create(unique_index(:faq_entries, [:question], name: :faq_entries_question_index))
  end
end
