defmodule Sanbase.Repo.Migrations.AddReviewFieldsToAiContext do
  use Ecto.Migration

  @moduledoc """
  Records what the AI bot review page needs to flag a turn.

  A row was saved as "ok" before the answer was posted, so an answer that
  failed to reach Discord or Telegram looked like a success. Tools that ran
  but returned nothing (e.g. a tweet search with no posts) were not visible
  either.
  """

  def change do
    alter table(:ai_context) do
      # "sent" | "failed". NULL for rows written before this column existed and
      # for turns where nothing was posted.
      add(:delivery_status, :string)
      add(:delivery_error, :text)
      # Problems the AI server reports per tool, e.g. "search_tweets:empty".
      add(:tool_issues, {:array, :string}, default: [])
    end

    # The review page reads one time window at a time.
    create(index(:ai_context, [:inserted_at]))
  end
end
