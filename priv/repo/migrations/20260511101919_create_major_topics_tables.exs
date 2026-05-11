defmodule Sanbase.Repo.Migrations.CreateMajorTopicsTables do
  use Ecto.Migration

  def change do
    create table(:topic_batches) do
      add(:source, :string, null: false)
      add(:interval_text, :string, null: false)
      add(:interval_start, :date, null: false)
      add(:interval_end, :date, null: false)
      add(:version, :integer, null: false, default: 1)
      add(:type, :string)
      add(:state, :string, null: false, default: "draft")
      add(:published_at, :utc_datetime)
      add(:published_by_id, references(:users, on_delete: :nilify_all))
      add(:fetched_at, :utc_datetime, null: false)

      timestamps()
    end

    create(unique_index(:topic_batches, [:source, :interval_text, :version]))
    create(index(:topic_batches, [:state, :published_at]))

    create table(:major_topics) do
      add(:batch_id, references(:topic_batches, on_delete: :delete_all), null: false)
      add(:ch_id, :text, null: false)
      add(:topic_id, :integer, null: false)
      add(:label, :text, null: false)
      add(:original_label, :text, null: false)
      add(:top_words, :text, null: false)
      add(:description, :text, null: false, default: "")
      add(:is_crypto_relevant, :boolean, null: false, default: true)
      add(:is_removed, :boolean, null: false, default: false)
      add(:position, :integer, null: false, default: 0)
      add(:values, :jsonb, null: false, default: "[]")

      timestamps()
    end

    create(index(:major_topics, [:batch_id]))
    create(unique_index(:major_topics, [:batch_id, :ch_id]))
  end
end
