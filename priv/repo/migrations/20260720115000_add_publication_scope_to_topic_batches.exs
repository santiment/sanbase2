defmodule Sanbase.Repo.Migrations.AddPublicationScopeToTopicBatches do
  use Ecto.Migration

  def up do
    alter table(:topic_batches) do
      add(:publication_scope, :string)
    end

    execute("""
    UPDATE topic_batches
    SET publication_scope = 'weekly_only'
    WHERE state = 'published'
    """)

    create(
      constraint(:topic_batches, :topic_batches_publication_scope_valid,
        check:
          "publication_scope IS NULL OR publication_scope IN ('daily_only', 'weekly_only', 'daily_weekly')"
      )
    )

    create(
      constraint(:topic_batches, :published_topic_batches_require_publication_scope,
        check: "state <> 'published' OR publication_scope IS NOT NULL"
      )
    )

    create(index(:topic_batches, [:state, :publication_scope, :interval_start]))
  end

  def down do
    drop(index(:topic_batches, [:state, :publication_scope, :interval_start]))

    drop(constraint(:topic_batches, :published_topic_batches_require_publication_scope))

    drop(constraint(:topic_batches, :topic_batches_publication_scope_valid))

    alter table(:topic_batches) do
      remove(:publication_scope, :string)
    end
  end
end
