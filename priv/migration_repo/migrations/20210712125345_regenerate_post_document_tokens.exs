defmodule Sanbase.Repo.Migrations.RegeneratePostDocumentTokens do
  use Ecto.Migration

  def up do
    Sanbase.Insight.Search.update_all_document_tokens()
  end

  def down do
    :ok
  end
end
