defmodule Sanbase.Repo.Migrations.AddFaqEntryReviewFields do
  use Ecto.Migration

  # Existing rows stay live, hence the `published` default.
  def change() do
    alter table(:faq_entries) do
      add(:status, :string, null: false, default: "published")
      add(:origin, :string, null: false, default: "admin")
      add(:internal_notes, :text)
      add(:created_by_id, references(:users, on_delete: :nilify_all))
      add(:reviewed_by_id, references(:users, on_delete: :nilify_all))
      add(:reviewed_at, :naive_datetime)
    end

    create(index(:faq_entries, [:status]))
  end
end
