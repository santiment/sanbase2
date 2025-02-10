defmodule Sanbase.Repo.Migrations.AddFieldsToPopularSearchTerms do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:popular_search_terms) do
      add(:title, :string, null: false)
      add(:options, :jsonb)

      timestamps()
    end
  end
end
