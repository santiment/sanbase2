defmodule Sanbase.Repo.Migrations.FaqEntriesQuestionUniqueAmongLive do
  use Ecto.Migration

  # Rejecting a draft soft-deletes it. Keep questions unique only among entries
  # that are not deleted, so a rejected question can be drafted again. The index
  # name is kept, as the changeset's unique_constraint refers to it.
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
