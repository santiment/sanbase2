defmodule Sanbase.Repo.Migrations.CreateAiReviewIssues do
  use Ecto.Migration

  @moduledoc """
  Problems found in AI bot turns, grouped by signature, so they can be polled,
  marked resolved, and noticed again when they come back.

  A signature names one kind of problem, e.g. `tool_issue:fetch_metric_data_tool:error`
  or `error:ai_server_http_500`. Every turn that shows it is linked to the issue.
  """

  def change do
    create table(:ai_review_issues) do
      add(:signature, :string, null: false)
      # One of the review flags: tool_issue, error, degraded, ...
      add(:flag, :string, null: false)
      # "open" | "resolved" | "recurred" (seen again after it was resolved)
      add(:status, :string, null: false, default: "open")
      add(:occurrences, :integer, null: false, default: 0)
      add(:recurrences, :integer, null: false, default: 0)
      add(:first_seen_at, :naive_datetime, null: false)
      add(:last_seen_at, :naive_datetime, null: false)
      add(:last_ai_context_id, references(:ai_context, on_delete: :nilify_all))
      add(:resolved_at, :utc_datetime)
      add(:resolved_by_id, references(:users, on_delete: :nilify_all))
      add(:resolution_note, :text)

      # updated_at is the polling cursor, so it keeps microseconds.
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:ai_review_issues, [:signature]))
    create(index(:ai_review_issues, [:updated_at]))

    create table(:ai_review_issue_turns, primary_key: false) do
      add(:issue_id, references(:ai_review_issues, on_delete: :delete_all), null: false)
      add(:ai_context_id, references(:ai_context, on_delete: :delete_all), null: false)
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create(unique_index(:ai_review_issue_turns, [:issue_id, :ai_context_id]))
    create(index(:ai_review_issue_turns, [:ai_context_id]))
  end
end
