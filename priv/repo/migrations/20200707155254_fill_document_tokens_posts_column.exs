defmodule Sanbase.Repo.Migrations.FillDocumentTokensPostsColumn do
  @moduledoc false
  use Ecto.Migration

  def up do
    setup()
    Sanbase.Insight.Search.update_all_document_tokens()
  end

  def down do
    :ok
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
  end
end
