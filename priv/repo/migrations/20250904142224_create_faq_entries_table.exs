defmodule Sanbase.Repo.Migrations.CreateFaqEntriesTable do
  use Ecto.Migration

  def change do
    create table(:faq_entries, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:question, :text, null: false)
      add(:answer_markdown, :text, null: false)
      add(:answer_html, :text, null: false)
      add(:source_url, :string)

      timestamps()
    end

    create(index(:faq_entries, [:updated_at]))
    create(index(:faq_entries, [:inserted_at]))
  end
end
