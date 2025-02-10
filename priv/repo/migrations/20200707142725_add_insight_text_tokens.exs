defmodule Sanbase.Repo.Migrations.AddInsightTextTokens do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table("posts") do
      # title || ' ' || text || ' ' || tags || ' ' || metrics || ' ' || user.username
      add(:document_tokens, :tsvector)
    end

    # Create a tsvector GIN index on PostgreSQL
    create(
      index("posts", [:document_tokens],
        name: :document_tokens_index,
        using: "GIN"
      )
    )
  end
end
